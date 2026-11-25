# frozen_string_literal: true

# The iOS / Android apps register their push token here after sign-in, and
# remove it on sign-out. Called from inside the app's web view, so it uses the
# normal session cookie and CSRF token.
#
# The app's web view remembers the token it registered in a signed cookie that
# outlives sign-out. That cookie is how we know a request comes from the phone
# that owns the token: only that phone can remove it while signed out, or move
# it to whoever signs in next. Knowing a token alone does neither.
class PushDevicesController < ApplicationController
  COOKIE = :push_device_token

  before_action :authenticate_user!, only: :create

  # POST /push_devices  { token:, platform: "apple" | "google", name: }
  def create
    token = params.require(:token).to_s
    device = ApplicationPushDevice.find_or_initialize_by(token: token)
    if device.persisted? && device.owner != current_user && !this_phone?(token)
      render json: { errors: [ "This device is registered to another account." ] }, status: :conflict
      return
    end

    device.assign_attributes(owner: current_user, platform: params.require(:platform), name: params[:name].to_s.first(100).presence)

    if device.save
      cookies.signed.permanent[COOKIE] = { value: token, httponly: true, same_site: :lax }
      # Remember which signed-in device owns the token, so signing that device
      # out (Settings → Security) stops its notifications too.
      UserDevice.where(id: Current.user_device_id, user_id: current_user.id).update_all(push_token: token) if Current.user_device_id
      head :created
    else
      render json: { errors: device.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /push_devices  { token: }
  # Allowed signed out too: the app calls it right after signing out.
  def destroy
    token = params.require(:token).to_s
    devices = ApplicationPushDevice.where(token: token)
    if user_signed_in? && !this_phone?(token)
      devices = devices.where(owner: current_user)
    elsif !this_phone?(token)
      devices = devices.none
    end
    devices.destroy_all
    head :no_content
  end

  private

  def this_phone?(token)
    remembered = cookies.signed[COOKIE].to_s
    remembered.present? && ActiveSupport::SecurityUtils.secure_compare(remembered, token)
  end
end
