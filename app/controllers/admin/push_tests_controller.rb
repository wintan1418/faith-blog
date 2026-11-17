# frozen_string_literal: true

# Admin → Push test: shows whether the server has the Apple / Google push keys
# and which of your phones are registered, and sends you a test notification
# right away (not through the job queue), showing what Apple or Google said.
class Admin::PushTestsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  def show
    @devices = current_user.push_devices.order(created_at: :desc)
    @results = flash[:push_results]
  end

  def create
    results = current_user.push_devices.order(created_at: :desc).map { |device| send_test(device) }
    results = [ "You have no phones registered. Open the app, allow notifications, and sign in again." ] if results.empty?
    redirect_to admin_push_test_path, flash: { push_results: results }
  end

  private

  def send_test(device)
    label = "#{device.platform == 'apple' ? 'iPhone' : 'Android'} “#{device.name || 'unnamed'}”"
    unless NativePushConfig.configured_platforms.include?(device.platform)
      return "#{label}: not sent — the server has no #{device.platform == 'apple' ? 'Apple (APNS_*)' : 'Google (FCM_*)'} push keys."
    end

    ApplicationPushNotification.new(title: "Brethreign", body: "Test notification from Admin → Push test.",
                                    sound: "default", data: { path: "/notifications" }).deliver_to(device)
    if ApplicationPushDevice.exists?(device.id)
      "#{label}: sent. It should arrive within a few seconds."
    else
      "#{label}: #{device.platform == 'apple' ? 'Apple' : 'Google'} rejected this phone's token, so it was removed. Sign out and in on the phone, then try again."
    end
  rescue StandardError => e
    "#{label}: failed — #{e.class.name.demodulize}: #{e.message.to_s.first(200)}"
  end
end
