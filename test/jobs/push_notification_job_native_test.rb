# frozen_string_literal: true

require "test_helper"

class PushNotificationJobNativeTest < ActiveJob::TestCase
  APPLE_ENV = { "APNS_KEY_ID" => "KEY123", "APNS_KEY" => "-----BEGIN PRIVATE KEY-----", "APNS_TEAM_ID" => "TEAM123" }.freeze

  setup do
    suffix = SecureRandom.hex(4)
    @user = User.create!(username: "user_#{suffix}", email: "user_#{suffix}@example.com",
                         password: "password123", password_confirmation: "password123")
    @follower = User.create!(username: "f_#{suffix}", email: "f_#{suffix}@example.com",
                             password: "password123", password_confirmation: "password123")
    @iphone = ApplicationPushDevice.create!(token: "iphone-token", platform: "apple", owner: @user)
    @android = ApplicationPushDevice.create!(token: "android-token", platform: "google", owner: @user)
  end

  def build_notification
    Notification.new(user: @user, actor: @follower, notifiable: @follower, notification_type: :new_follower)
                .tap { |n| n.save!(validate: false) }
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  test "sends to the user's iPhone, with the page to open, once Apple keys are set" do
    notification = build_notification
    with_env(APPLE_ENV) do
      assert_enqueued_jobs 1, only: ApplicationPushNotificationJob do
        PushNotificationJob.perform_now(notification)
      end
    end

    job = enqueued_jobs.find { |j| j["job_class"] == "ApplicationPushNotificationJob" }
    payload = job["arguments"][1]
    assert_equal "Brethreign", payload["title"]
    assert_equal "/u/#{@follower.username}", payload.dig("data", "path")
  end

  test "skips the apps when no push keys are configured" do
    notification = build_notification
    with_env(APPLE_ENV.transform_values { nil }) do
      assert_no_enqueued_jobs only: ApplicationPushNotificationJob do
        PushNotificationJob.perform_now(notification)
      end
    end
  end
end
