# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Two-step login with an authenticator app, recovery codes, trusted devices,
# and how it fits with Google / Apple, password reset and the lock.
class TwoFactorTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  setup { ActionMailer::Base.deliveries.clear }

  test "turning it on: scan, prove a code, see the recovery codes once, get an email" do
    user, = security_member("tf_setup")
    sign_in user
    get new_settings_two_factor_path
    assert_response :success
    assert_select ".sec-qr svg"
    assert_select "a[href^='otpauth://totp/Brethreign']", "Open in authenticator app"
    secret = css_select(".sec-key code").text.delete(" ")

    post settings_two_factor_path, params: { code: "123456" == totp_now(secret) ? "654321" : "123456" }
    assert_response :unprocessable_entity
    assert_not user.reload.two_factor_enabled?

    mails = mails_during { post settings_two_factor_path, params: { code: totp_now(secret) } }
    assert_redirected_to recovery_codes_settings_two_factor_path
    assert user.reload.two_factor_enabled?
    assert_equal 10, user.recovery_codes_left
    assert mails.any? { |m| m.subject == "Two-step login is on for your Brethreign account" }

    follow_redirect!
    codes = css_select(".sec-recovery code").map(&:text)
    assert_equal 10, codes.size
    get recovery_codes_settings_two_factor_path
    assert_redirected_to settings_security_path, "shown only once"
    assert_not_includes user.reload.otp_secret_ciphertext, secret, "the secret is stored encrypted"
  end

  test "sign-in asks for the app code; a trusted device skips it for 30 days" do
    user, password = security_member("tf_signin")
    enable_two_factor_for(user)
    password_sign_in(user, password)
    assert_redirected_to sign_in_check_path
    assert_not ActionMailer::Base.deliveries.any? { |m| m.subject.include?("sign-in code") }, "no email code when the app is on"
    get sign_in_check_path
    assert_select "h1", "Two-step login"

    post sign_in_check_path, params: { code: totp_now(user), trust_device: "1" }
    assert_redirected_to feed_path
    assert user.user_devices.last.trusted?

    delete destroy_user_session_path
    password_sign_in(user, password)
    assert_redirected_to feed_path, "trusted device"

    delete destroy_user_session_path
    travel 31.days
    password_sign_in(user, password)
    assert_redirected_to sign_in_check_path, "trust runs out"
  end

  test "right after turning it on, the next code from the app works" do
    user, password = security_member("tf_next_step")
    secret = AccountSecurity.new_otp_secret
    step = AccountSecurity.verify_totp(secret, totp_now(secret))
    user.enable_two_factor!(secret, step)
    password_sign_in(user, password)
    post sign_in_check_path, params: { code: totp_now(secret, at: Time.current + 30) }
    assert_redirected_to feed_path
  end

  test "an app code can't be used twice" do
    user, password = security_member("tf_replay")
    enable_two_factor_for(user)
    code = totp_now(user)
    password_sign_in(user, password)
    post sign_in_check_path, params: { code: code }
    assert_redirected_to feed_path
    delete destroy_user_session_path

    password_sign_in(user, password)
    post sign_in_check_path, params: { code: code }
    assert_response :unprocessable_entity
  end

  test "recovery codes work once each" do
    user, password = security_member("tf_recovery")
    codes = enable_two_factor_for(user)
    password_sign_in(user, password)
    post sign_in_check_path, params: { code: "", recovery_code: codes.first.upcase.delete("-") }
    assert_redirected_to feed_path
    assert_equal 9, user.reload.recovery_codes_left
    delete destroy_user_session_path

    password_sign_in(user, password)
    post sign_in_check_path, params: { recovery_code: codes.first }
    assert_response :unprocessable_entity
    assert_select ".auth-errors", /recovery code didn't work/
  end

  test "wrong app codes count towards the lock" do
    user, password = security_member("tf_lock")
    enable_two_factor_for(user)
    password_sign_in(user, password)
    mails = mails_during do
      Devise.maximum_attempts.times { post sign_in_check_path, params: { code: "000000" } }
    end
    assert user.reload.access_locked?
    assert_redirected_to new_user_session_path
    assert mails.any? { |m| m.subject.include?("locked") }
  end

  test "turning it off needs the password or a code, and emails the member" do
    user, password = security_member("tf_off")
    enable_two_factor_for(user)
    sign_in user
    delete settings_two_factor_path, params: { current_password: "wrong" }
    assert user.reload.two_factor_enabled?

    mails = mails_during { delete settings_two_factor_path, params: { current_password: password } }
    assert_not user.reload.two_factor_enabled?
    assert mails.any? { |m| m.subject == "Two-step login is off for your Brethreign account" }
  end

  test "new recovery codes need a current code" do
    user, = security_member("tf_regen")
    old = enable_two_factor_for(user)
    sign_in user
    post recovery_codes_settings_two_factor_path, params: { code: "000000" }
    assert_redirected_to settings_security_path(anchor: "two-step")
    post recovery_codes_settings_two_factor_path, params: { code: totp_now(user) }
    assert_redirected_to recovery_codes_settings_two_factor_path
    assert_not user.reload.use_recovery_code!(old.first), "old codes stop working"
  end

  test "Google in the app still asks for the app code (the app follows location)" do
    user = User.from_google(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-tf-1",
                                                   info: { email: "gtf@example.com", name: "G TF" }))
    enable_two_factor_for(user)
    previous, ENV["GOOGLE_CLIENT_ID"] = ENV["GOOGLE_CLIENT_ID"], "web-client.apps.googleusercontent.com"
    payload = { "sub" => "g-tf-1", "email" => "gtf@example.com", "email_verified" => true, "name" => "G TF" }
    Google::Auth::IDTokens.stub(:verify_oidc, ->(_t, aud:) { payload }) do
      post native_google_sign_in_path, params: { id_token: "tok" }, as: :json,
                                       headers: { "User-Agent" => "Hotwire Native Android; Turbo Native Android" }
    end
    assert_equal sign_in_check_path, response.parsed_body["location"]
    get feed_path
    assert_redirected_to new_user_session_path

    get sign_in_check_path, headers: { "User-Agent" => "Hotwire Native Android; Turbo Native Android" }
    assert_select "body.hotwire-native"
    post sign_in_check_path, params: { code: totp_now(user) }
    assert_redirected_to feed_path
  ensure
    ENV["GOOGLE_CLIENT_ID"] = previous
  end

  test "Sign in with Apple in the app still asks for the app code" do
    key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(key, kid: "tf-key")
    user = User.from_google(OmniAuth::AuthHash.new(provider: "apple", uid: "apple-tf", info: { email: "atf@privaterelay.appleid.com" }))
    enable_two_factor_for(user)
    claims = { iss: "https://appleid.apple.com", aud: "com.brethreign.app", sub: "apple-tf", email: "atf@privaterelay.appleid.com",
               email_verified: "true", iat: Time.now.to_i, exp: 10.minutes.from_now.to_i }
    token = JWT.encode(claims, jwk.signing_key, "RS256", kid: jwk.kid)
    AppleIdentityToken.stub(:jwks, ->(_opts = {}) { JWT::JWK::Set.new(keys: [ jwk.export ]) }) do
      post native_apple_sign_in_path, params: { identity_token: token }, as: :json
    end
    assert_equal sign_in_check_path, response.parsed_body["location"]
  end

  test "a password reset doesn't skip two-step login" do
    user, = security_member("tf_reset")
    enable_two_factor_for(user)
    token = user.send(:set_reset_password_token)
    new_password = SecureRandom.base58(16)
    put user_password_path, params: { user: { reset_password_token: token, password: new_password, password_confirmation: new_password } }
    assert_redirected_to sign_in_check_path
    get feed_path
    assert_redirected_to new_user_session_path
    post sign_in_check_path, params: { code: totp_now(user) }
    assert_redirected_to feed_path
  end

  test "the code screens work inside the apps" do
    user, password = security_member("tf_native")
    enable_two_factor_for(user)
    native = { "User-Agent" => "Brethreign/1.0.13 Hotwire Native iOS; Turbo Native iOS" }
    password_sign_in(user, password, headers: native)
    get sign_in_check_path, headers: native
    assert_select "body.hotwire-native"
    assert_select "form[data-turbo=true] input[name=code]"
  end
end
