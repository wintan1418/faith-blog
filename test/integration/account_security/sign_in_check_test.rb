# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# "Is this you?": a password sign-in from a device we don't recognise asks for
# a code emailed to the (verified) address. Nobody is locked out by it.
class SignInCheckTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

  setup { ActionMailer::Base.deliveries.clear }

  test "a new device asks for an emailed code, then remembers the device" do
    user, password = security_member("device_owner")
    mails = mails_during { password_sign_in(user, password, headers: { "User-Agent" => CHROME_WINDOWS, "CF-IPCountry" => "NG", "CF-IPCity" => "Lagos" }) }
    assert_redirected_to sign_in_check_path
    code_mail = mails.find { |m| m.subject.include?("sign-in code") }
    assert code_mail
    assert_includes code_mail.text_part.body.to_s, "Chrome on Windows near Lagos, Nigeria"

    get feed_path
    assert_redirected_to new_user_session_path, "not signed in until the code is entered"

    get sign_in_check_path, headers: { "User-Agent" => CHROME_WINDOWS }
    assert_select "h1", "Is this you?"
    assert_select ".sec-device-card", /Chrome on Windows/
    assert_select "input[name=trust_device][checked]"

    alert = mails_during { post sign_in_check_path, params: { code: emailed_code, trust_device: "1" }, headers: { "User-Agent" => CHROME_WINDOWS } }
    assert_redirected_to feed_path
    assert alert.any? { |m| m.subject == "New sign-in to your Brethreign account" }, "new-device alert"
    get feed_path
    assert_response :success

    # Same browser next time: no code.
    delete destroy_user_session_path
    password_sign_in(user, password)
    assert_redirected_to feed_path
    assert_equal 1, user.user_devices.count
    assert user.user_devices.first.recognised?
  end

  test "without Trust this device, the next sign-in asks again" do
    user, password = security_member("no_trust")
    perform_enqueued_jobs { password_sign_in(user, password) }
    post sign_in_check_path, params: { code: emailed_code }
    assert_redirected_to feed_path
    delete destroy_user_session_path

    password_sign_in(user, password)
    assert_redirected_to sign_in_check_path
  end

  test "wrong codes are refused, and a wrong password never reaches the check" do
    user, password = security_member("wrong_codes")
    perform_enqueued_jobs { password_sign_in(user, password) }
    code = emailed_code
    post sign_in_check_path, params: { code: code == "000000" ? "111111" : "000000" }
    assert_response :unprocessable_entity
    assert_select ".auth-errors", /didn't match/
    assert SecurityEvent.exists?(user: user, kind: "code_failed")

    delete sign_in_check_path
    password_sign_in(user, "not-the-password")
    assert_response :unprocessable_entity
    assert_nil session[SignInChecks::PENDING_KEY]
    assert_equal 1, user.reload.failed_attempts, "counted once, like before"
  end

  test "resend waits out the cooldown" do
    user, password = security_member("resender")
    perform_enqueued_jobs { password_sign_in(user, password) }
    post resend_sign_in_check_path
    assert_match(/Please wait/, flash[:alert])
    travel 61.seconds
    mails = mails_during { post resend_sign_in_check_path }
    assert_redirected_to sign_in_check_path
    assert_equal 1, mails.count { |m| m.subject.include?("sign-in code") }
  end

  test "the half-finished sign-in expires, and a password change cancels it" do
    user, password = security_member("expiring")
    password_sign_in(user, password)
    travel 16.minutes
    get sign_in_check_path
    assert_redirected_to new_user_session_path

    travel_back
    password_sign_in(user, password)
    user.update!(password: SecureRandom.base58(16))
    get sign_in_check_path
    assert_redirected_to new_user_session_path
  end

  test "no lockout: unverified members sign in straight away (and just get the alert)" do
    user, password = security_member("unverified_signin", verified: false)
    mails = mails_during { password_sign_in(user, password) }
    assert_redirected_to feed_path
    assert_not mails.any? { |m| m.subject.include?("sign-in code") }
    assert mails.any? { |m| m.subject == "New sign-in to your Brethreign account" }
  end

  test "no lockout: members already signed in before the rollout stay signed in" do
    user, = security_member("legacy_session")
    # A session from before devices were tracked: signed in, no device token.
    AccountDevices.stub(:signed_in!, nil) do
      sign_in user
      get rooms_path
    end
    assert_equal 0, user.user_devices.count
    get feed_path
    assert_response :success
    assert_equal 1, user.user_devices.signed_in.count, "the old session was adopted quietly"
    assert_not SecurityEvent.exists?(user: user, kind: "sign_in", device_name: nil)
  end

  test "Google sign-in skips the code but still alerts on a new device" do
    google = User.from_google(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-alert-1",
                                                     info: { email: "galert@example.com", name: "G Alert" }))
    ENV["GOOGLE_CLIENT_ID"], previous = "web-client.apps.googleusercontent.com", ENV["GOOGLE_CLIENT_ID"]
    payload = { "sub" => "g-alert-1", "email" => "galert@example.com", "email_verified" => true, "name" => "G Alert" }
    mails = mails_during do
      Google::Auth::IDTokens.stub(:verify_oidc, ->(_t, aud:) { payload }) do
        post native_google_sign_in_path, params: { id_token: "tok" }, as: :json,
                                         headers: { "User-Agent" => "Hotwire Native Android; Turbo Native Android" }
      end
    end
    assert_response :success
    assert_equal feed_path, response.parsed_body["location"]
    assert mails.any? { |m| m.subject == "New sign-in to your Brethreign account" && m.to == [ google.email ] }
    assert_equal "Brethreign app on Android", google.user_devices.last.name
  ensure
    ENV["GOOGLE_CLIENT_ID"] = previous
  end

  test "the apps can send a stable install id instead of relying on the cookie" do
    user, password = security_member("app_install")
    headers = { "User-Agent" => "Brethreign/1.0.13 Hotwire Native iOS; Turbo Native iOS", AccountDevices::INSTALL_HEADER => "install-1234567890abcdef" }
    perform_enqueued_jobs { password_sign_in(user, password, headers: headers) }
    assert_redirected_to sign_in_check_path
    post sign_in_check_path, params: { code: emailed_code, trust_device: "1" }, headers: headers
    delete destroy_user_session_path, headers: headers
    cookies.delete(AccountDevices::COOKIE)

    password_sign_in(user, password, headers: headers)
    assert_redirected_to feed_path, "recognised by the install id"
  end

  test "the site monitor is never stopped or tracked" do
    monitor = User.find(SiteHealthCheck.monitor_user.id)
    monitor.mark_email_verified!
    password = SecureRandom.base58(20)
    monitor.update!(password: password)
    password_sign_in(monitor, password)
    assert_redirected_to feed_path
    assert_equal 0, monitor.user_devices.count
  end

  test "lockout still works with the new sign-in: ten wrong passwords lock the account" do
    user, password = security_member("lock_me")
    mails = mails_during { 10.times { password_sign_in(user, "wrong-#{SecureRandom.hex(4)}") } }
    assert user.reload.access_locked?
    assert mails.any? { |m| m.subject.include?("locked") }, "the branded unlock email"
    AuthThrottleStore.clear!
    password_sign_in(user, password)
    assert_nil session[SignInChecks::PENDING_KEY], "a locked account never reaches the code screen"
    assert_response :unprocessable_entity
  end

  test "a rate-limited sign-in never signs in, even with the right password" do
    user, password = security_member("rate_limited")
    # This IP used up its tries on other addresses (so the account isn't locked).
    10.times { |i| post user_session_path, params: { user: { email: "someone#{i}@example.com", password: "x" } } }
    password_sign_in(user, password)
    assert_response :too_many_requests
    assert_nil session[SignInChecks::PENDING_KEY]
    get feed_path
    assert_redirected_to new_user_session_path
    assert_equal 0, user.user_devices.count
  end
end
