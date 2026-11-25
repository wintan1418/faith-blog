# frozen_string_literal: true

# Settings → Security: email verification, two-step login, and the devices
# signed in to the account.
class Settings::SecuritiesController < ApplicationController
  before_action :authenticate_user!

  def show
    @devices = current_user.user_devices.by_recent.to_a
    @current_device_id = Current.user_device_id
    @signed_in_devices, @past_devices = @devices.partition(&:signed_in?)
    @past_devices = @past_devices.first(10)
  end
end
