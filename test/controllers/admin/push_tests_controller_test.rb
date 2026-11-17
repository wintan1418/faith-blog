# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Admin → Push test: says whether the push keys are set, lists your phones,
# and reports what happened when it sent you a test notification.
class Admin::PushTestsControllerTest < ActionDispatch::IntegrationTest
  APPLE_ENV = { "APNS_KEY_ID" => "KEY123", "APNS_KEY" => "-----BEGIN PRIVATE KEY-----", "APNS_TEAM_ID" => "TEAM123" }.freeze

  setup do
    @admin = create_member("push_admin_#{SecureRandom.hex(3)}", role: :admin)
    sign_in @admin
  end

  test "lists your phones and says when there are none" do
    get admin_push_test_path
    assert_response :success
    assert_match "None yet", response.body

    @admin.push_devices.create!(token: "abc123", platform: "apple", name: "Juwon's iPhone")
    get admin_push_test_path
    assert_match "Juwon&#39;s iPhone", response.body
  end

  test "reports a missing key, a sent push, and a token Apple rejected" do
    device = @admin.push_devices.create!(token: "abc123", platform: "apple", name: "Phone")
    saved = APPLE_ENV.keys.to_h { |k| [ k, ENV[k] ] }

    APPLE_ENV.each_key { |k| ENV[k] = nil }
    post admin_push_test_path
    follow_redirect!
    assert_match "no Apple (APNS_*) push keys", response.body

    APPLE_ENV.each { |k, v| ENV[k] = v }
    sent = ->(_device) { nil }
    ApplicationPushNotification.class_eval { alias_method :__real_deliver_to, :deliver_to }
    ApplicationPushNotification.define_method(:deliver_to, &sent)
    post admin_push_test_path
    follow_redirect!
    assert_match "sent. It should arrive", response.body

    ApplicationPushNotification.define_method(:deliver_to) { |d| d.destroy! }
    post admin_push_test_path
    follow_redirect!
    assert_match "rejected this phone", response.body
    assert_not ApplicationPushDevice.exists?(device.id)
  ensure
    if ApplicationPushNotification.method_defined?(:__real_deliver_to)
      ApplicationPushNotification.class_eval do
        alias_method :deliver_to, :__real_deliver_to
        remove_method :__real_deliver_to
      end
    end
    saved&.each { |k, v| ENV[k] = v }
  end
end
