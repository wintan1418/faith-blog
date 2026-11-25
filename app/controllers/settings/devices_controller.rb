# frozen_string_literal: true

# Signing out other devices from Settings → Security.
class Settings::DevicesController < ApplicationController
  include Devise::Controllers::Rememberable
  before_action :authenticate_user!

  # DELETE /settings/devices/:id — sign out one other device.
  def destroy
    device = current_user.user_devices.find(params[:id])
    if device.id == Current.user_device_id
      return redirect_to(settings_security_path, status: :see_other, alert: "That's this device. Use Sign out in the menu instead.")
    end

    AccountDevices.sign_out_device!(current_user, device)
    keep_this_device_remembered
    SecurityEvent.record!(:device_signed_out, user: current_user, request: request, device: device.name)
    redirect_to settings_security_path, status: :see_other, notice: "#{device.name} has been signed out."
  end

  # DELETE /settings/devices — "Sign out everywhere else".
  def destroy_others
    AccountDevices.sign_out_others!(current_user, request)
    keep_this_device_remembered
    SecurityEvent.record!(:signed_out_everywhere, user: current_user, request: request)
    redirect_to settings_security_path, status: :see_other, notice: "Every other device has been signed out."
  end

  private

  # Signing out elsewhere retires every remember-me cookie; give this browser a fresh one.
  def keep_this_device_remembered
    remember_me(current_user) if cookies[:remember_user_token].present?
  end
end
