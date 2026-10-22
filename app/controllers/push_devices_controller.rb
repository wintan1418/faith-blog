# frozen_string_literal: true

# The iOS / Android apps register their push token here after sign-in, and
# remove it on sign-out. Called from inside the app's web view, so it uses the
# normal session cookie and CSRF token.
class PushDevicesController < ApplicationController
  before_action :authenticate_user!, only: :create

  # POST /push_devices  { token:, platform: "apple" | "google", name: }
  def create
    device = ApplicationPushDevice.find_or_initialize_by(token: params.require(:token))
    device.assign_attributes(owner: current_user, platform: params.require(:platform), name: params[:name].to_s.first(100).presence)

    if device.save
      head :created
    else
      render json: { errors: device.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /push_devices  { token: }
  # Allowed signed out too: the app calls it right after signing out.
  def destroy
    ApplicationPushDevice.where(token: params.require(:token)).destroy_all
    head :no_content
  end
end
