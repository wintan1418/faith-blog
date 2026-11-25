# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Settings → Security → Devices & sessions: the list, signing one device out,
# "Sign out everywhere else", and push tokens of signed-out phones.
class DevicesTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  PHONE = { "User-Agent" => "Brethreign/1.0.13 Hotwire Native Android; Turbo Native Android" }

  test "the list shows each device, this one first-class, with approximate places" do
    user, = security_member("dev_list")
    sign_in user
    get settings_security_path, headers: { "CF-IPCountry" => "NG" }
    assert_response :success
    assert_select ".sec-device.is-current .sec-device-name", /This device/
    assert_select ".settings-tab.is-active", "Security"
  end

  test "signing out another device ends its session and stops its notifications" do
    user, password = security_member("dev_remote", verified: false)
    # The phone signs in and registers for push.
    phone = open_session
    phone.post user_session_path, params: { user: { email: user.email, password: password } }, headers: PHONE
    phone.post push_devices_path, params: { token: "phone-push-token", platform: "google" }, headers: PHONE
    assert_equal 201, phone.response.status
    phone_device = user.user_devices.find_by!(name: "Brethreign app on Android")
    assert_equal "phone-push-token", phone_device.push_token

    # The laptop signs it out.
    password_sign_in(user, password)
    get settings_security_path
    assert_select ".sec-device", /Brethreign app on Android/
    delete settings_device_path(phone_device)
    assert_redirected_to settings_security_path
    assert_not ApplicationPushDevice.exists?(token: "phone-push-token")
    assert_not phone_device.reload.recognised?, "whoever has it must prove themselves again"

    phone.get feed_path, headers: PHONE
    assert_equal 303, phone.response.status
    assert_equal new_user_session_url, phone.response.location
    get feed_path
    assert_response :success, "this device stays signed in"
  end

  test "you can't sign out this device from the list" do
    user, = security_member("dev_self")
    sign_in user
    get feed_path
    delete settings_device_path(user.user_devices.first)
    assert_redirected_to settings_security_path
    get feed_path
    assert_response :success
  end

  test "Sign out everywhere else: other devices, old sessions and remember-me cookies" do
    user, password = security_member("dev_everywhere", verified: false)
    other = open_session
    other.post user_session_path, params: { user: { email: user.email, password: password, remember_me: "1" } }, headers: PHONE
    ApplicationPushDevice.create!(owner: user, token: "old-phone", platform: "google")

    password_sign_in(user, password)
    delete others_settings_devices_path
    assert_redirected_to settings_security_path
    assert user.reload.sessions_reset_at
    assert_equal 1, user.user_devices.signed_in.count
    assert_not ApplicationPushDevice.exists?(token: "old-phone")

    other.get feed_path, headers: PHONE
    assert_equal new_user_session_url, other.response.location
    # Its remember-me cookie no longer signs it back in.
    other.get feed_path, headers: PHONE
    assert_equal 302, other.response.status
    get feed_path
    assert_response :success
  end

  test "a session from before devices were tracked ends after Sign out everywhere else" do
    user, = security_member("dev_legacy")
    AccountDevices.stub(:signed_in!, nil) do
      sign_in user
      get rooms_path
    end
    user.update_columns(sessions_reset_at: Time.current)
    get feed_path
    assert_redirected_to new_user_session_path
  end

  test "changing the password marks other devices signed out" do
    user, password = security_member("dev_pw", verified: false)
    other = open_session
    other.post user_session_path, params: { user: { email: user.email, password: password } }, headers: PHONE
    assert_equal feed_url, other.response.location

    password_sign_in(user, password)
    user.mark_email_verified! # changing the password needs a verified email
    new_password = SecureRandom.base58(16)
    patch settings_account_path, params: { user: { password: new_password, password_confirmation: new_password, current_password: password } }
    assert_equal 1, user.reload.user_devices.signed_in.count
    get feed_path
    assert_response :success
    other.get feed_path, headers: PHONE
    assert_equal new_user_session_url, other.response.location
  end

  test "two sign-ins racing on the same browser don't sign it out" do
    user, password = security_member("dev_race", verified: false)
    password_sign_in(user, password)
    device = user.user_devices.sole
    # Another request on this browser signed in at the same moment and its token won.
    device.update_columns(session_digest: AccountDevices.digest("another-token"))
    get feed_path
    assert_response :success

    # But once the device is signed out, it's out.
    device.sign_out!
    get feed_path
    assert_redirected_to new_user_session_path
  end
end
