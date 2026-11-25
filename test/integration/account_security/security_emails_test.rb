# frozen_string_literal: true

require "test_helper"

# The security emails (all branded, all with "Wasn't you?") and the
# "Secure my account" link they carry.
class SecurityEmailsTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  setup { ActionMailer::Base.deliveries.clear }

  def assert_security_email(mail)
    html = mail.html_part.body.to_s
    assert_includes html, "brand/brethreign-logo-darkg.png", "#{mail.subject}: the logo layout"
    assert_includes html, "Wasn't you?", "#{mail.subject}: Wasn't you? help"
    assert_match %r{/secure-account/}, html
    assert_no_match(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, mail.text_part.body.to_s, "never an IP address")
  end

  test "password changed" do
    user, password = security_member("em_pw")
    sign_in user
    new_password = SecureRandom.base58(16)
    mails = mails_during do
      patch settings_account_path, params: { user: { password: new_password, password_confirmation: new_password, current_password: password } }
    end
    mail = mails.find { |m| m.subject == "Your Brethreign password was changed" }
    assert_security_email(mail)
    assert_not mails.any? { |m| m.subject.include?("Password Changed") }, "not Devise's plain one too"
  end

  test "email changed: the old address is told and can switch it back" do
    user, password = security_member("em_change")
    sign_in user
    perform_enqueued_jobs { patch settings_account_path, params: { user: { email: "em_new@example.com", current_password: password } } }
    mails = mails_during { patch settings_email_change_path, params: { code: emailed_code(to: "em_new@example.com") } }
    notice = mails.find { |m| m.to == [ "em_change@example.com" ] }
    assert_equal "Your Brethreign email address was changed", notice.subject
    assert_security_email(notice)
    assert_includes notice.text_part.body.to_s, "e•••••@example.com"

    link = notice.text_part.body.to_s[%r{http://\S+/secure-account/\S+}]
    get URI(link).path
    assert_select "li", /Switch your email back to/
    mails = mails_during { post URI(link).path }
    assert_redirected_to new_user_session_path
    assert_equal "em_change@example.com", user.reload.email
    assert mails.any? { |m| m.subject == "Choose a new Brethreign password" && m.to == [ "em_change@example.com" ] }
    get feed_path
    assert_redirected_to new_user_session_path, "signed out everywhere, here too"
  end

  test "two-step login on and off" do
    user, password = security_member("em_2fa")
    sign_in user
    get new_settings_two_factor_path
    secret = css_select(".sec-key code").text.delete(" ")
    on = mails_during { post settings_two_factor_path, params: { code: totp_now(secret) } }
    assert_security_email(on.find { |m| m.subject.start_with?("Two-step login is on") })
    off = mails_during { delete settings_two_factor_path, params: { current_password: password } }
    assert_security_email(off.find { |m| m.subject.start_with?("Two-step login is off") })
  end

  test "locked and unlocked" do
    user, password = security_member("em_lock")
    locked = mails_during { 10.times { password_sign_in(user, "nope-#{SecureRandom.hex(3)}") } }
    mail = locked.find { |m| m.subject == "Your Brethreign account is locked for a while" }
    assert mail
    assert_includes mail.html_part.body.to_s, "brand/brethreign-logo-darkg.png"
    assert_includes mail.html_part.body.to_s, "Wasn't you?"

    unlocked = mails_during { user.reload.unlock_access! }
    assert_security_email(unlocked.find { |m| m.subject == "Your Brethreign account is unlocked" })
  end

  test "new sign-in alert names the device, the rough place and the time" do
    user, password = security_member("em_alert", verified: false)
    mails = mails_during do
      password_sign_in(user, password, headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
                                                  "CF-IPCountry" => "NG" })
    end
    mail = mails.find { |m| m.subject == "New sign-in to your Brethreign account" }
    assert_security_email(mail)
    assert_includes mail.text_part.body.to_s, "Chrome on Windows"
    assert_includes mail.text_part.body.to_s, "Nigeria"
    assert_includes mail.text_part.body.to_s, "WAT"

    # The same browser again: no alert.
    delete destroy_user_session_path
    again = mails_during { password_sign_in(user, password) }
    assert_not again.any? { |m| m.subject.start_with?("New sign-in") }
  end

  test "Secure my account: everything signed out, password off, two-step off, reset link sent" do
    user, password = security_member("em_secure")
    enable_two_factor_for(user)
    token = user.secure_account_token
    get secure_account_path(token: token)
    assert_response :success
    mails = mails_during { post secure_account_path(token: token) }
    user.reload
    assert_not user.valid_password?(password)
    assert_not user.two_factor_enabled?
    assert user.sessions_reset_at
    assert mails.any? { |m| m.subject == "Choose a new Brethreign password" }
    assert SecurityEvent.exists?(user: user, kind: "account_secured")

    get secure_account_path(token: "tampered")
    assert_redirected_to new_user_password_path
  end

  test "the welcome email: logo layout, three first steps, app store links when set" do
    user, = security_member("em_welcome")
    previous = ENV["IOS_STORE_URL"]
    ENV["IOS_STORE_URL"] = "https://apps.apple.com/app/brethreign/id6835821959"
    mail = WelcomeMailer.with(user: user).welcome
    html = mail.html_part.body.to_s
    assert_includes html, "brand/brethreign-logo-darkg.png"
    [ "Complete your profile", "Read today&#39;s chapter", "Join a Room" ].each { |step| assert_includes html, step }
    assert_includes html, "/settings/profile/edit"
    assert_includes html, "/rooms"
    assert_includes html, "Download on the App Store"
    assert_not_includes html, "Google Play", "Android link only once ANDROID_STORE_URL is set"
  ensure
    ENV["IOS_STORE_URL"] = previous
  end
end
