# frozen_string_literal: true

require "test_helper"

# Verifying the email address: after sign-up, from the banner, by code or the
# one-tap link; and what needs a verified email (and what doesn't).
class EmailVerificationTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  setup { ActionMailer::Base.deliveries.clear }

  test "sign-up shows Check your email, sends a code, and the code verifies the address" do
    mails = mails_during do
      post user_registration_path, params: { user: { username: "fresh_join", email: "fresh_join@example.com",
                                                     password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    end
    assert_redirected_to email_verification_path
    user = User.find_by!(username: "fresh_join")
    assert_not user.email_verified?
    code_mail = mails.find { |m| m.subject.include?("verification code") }
    assert code_mail, "a verification code email"
    assert_includes code_mail.html_part.body.to_s, "brand/brethreign-logo-darkg.png", "branded layout"
    assert_includes code_mail.html_part.body.to_s, "/verify-email/", "one-tap link"
    assert_not mails.any? { |m| m.subject.include?("New sign-in") }, "no new-device alert for a brand-new account"

    follow_redirect!
    assert_select "h1", "Check your email"
    assert_select "input[name=code][autocomplete=one-time-code][inputmode=numeric]"

    patch email_verification_path, params: { code: "000000" == emailed_code ? "111111" : "000000" }
    assert_response :unprocessable_entity
    assert_select ".auth-errors", /didn't match/

    patch email_verification_path, params: { code: emailed_code }
    assert_redirected_to feed_path
    assert user.reload.email_verified?
  end

  test "the one-tap link verifies, even in another browser, and only once" do
    user, = security_member("link_tapper", verified: false)
    perform_enqueued_jobs { EmailVerification.send_code!(user) }
    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://\S+/verify-email/\S+}]
    get URI(link).path
    assert_redirected_to new_user_session_path
    assert user.reload.email_verified?

    get URI(link).path
    assert_redirected_to new_user_session_path
    assert_match(/expired or was already used/, flash[:alert])
  end

  test "existing unverified members aren't blocked: a gentle banner, dismissible for the week" do
    user, = security_member("old_member", verified: false)
    sign_in user
    get feed_path
    assert_response :success
    assert_select ".sec-verify-banner", /Verify your email to keep your account safe/
    assert_select ".sec-verify-banner a[href^=?]", email_verification_path

    user.dismiss_card!("verify-email-w#{Date.current.cweek}")
    get feed_path
    assert_select ".sec-verify-banner", count: 0

    get rooms_path
    assert_response :success
  end

  test "verified members and Google / Apple members never see the banner" do
    google = User.from_google(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-ver-1",
                                                     info: { email: "gverified@example.com", name: "G Verified" }))
    assert google.email_verified?, "Google proved the address"
    sign_in google
    get feed_path
    assert_select ".sec-verify-banner", count: 0
  end

  test "sending a code is limited: one a minute" do
    user, = security_member("impatient", verified: false)
    sign_in user
    mails = mails_during { post email_verification_path }
    assert_redirected_to email_verification_path
    assert_equal 1, mails.count { |m| m.subject.include?("verification code") }

    post email_verification_path
    assert_match(/Please wait/, flash[:alert])
    assert_equal 1, SecurityCode.where(user: user).count

    get email_verification_path
    assert_select "button[disabled]", /Send a new code/
  end

  test "sensitive actions ask for a verified email first: password change, two-step login, a Page" do
    user, password = security_member("needs_verify", verified: false, created_at: 30.days.ago)
    sign_in user

    new_password = SecureRandom.base58(16)
    patch settings_account_path, params: { user: { password: new_password, password_confirmation: new_password, current_password: password } }
    assert_response :unprocessable_entity
    assert_match(/verify your email/, response.body)
    assert user.reload.valid_password?(password)

    get new_settings_two_factor_path
    assert_redirected_to email_verification_path(return_to: new_settings_two_factor_path)

    get new_org_page_path
    assert_select ".pg-blocked a[href^=?]", email_verification_path
  end

  test "admins can still do their admin work unverified, and may make pages" do
    admin, = security_member("unverified_admin", verified: false, role: :admin)
    sign_in admin
    get admin_users_path
    assert_response :success
    assert_nil Page.creation_block_reason(admin)
  end

  test "a password reset proves the inbox, so it verifies the email" do
    user, = security_member("resetter", verified: false)
    token = user.send(:set_reset_password_token)
    new_password = SecureRandom.base58(16)
    put user_password_path, params: { user: { reset_password_token: token, password: new_password, password_confirmation: new_password } }
    assert user.reload.email_verified?
  end
end
