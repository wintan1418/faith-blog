# frozen_string_literal: true

require "test_helper"

# Apple requires apps with Sign in with Apple to revoke the person's token when
# they delete their account. We keep the refresh token from sign-in and revoke
# it on deletion.
class AppleSignInTokensTest < ActiveSupport::TestCase
  KEY = OpenSSL::PKey::EC.generate("prime256v1")
  ENV_VARS = { "APNS_KEY" => KEY.private_to_pem, "APNS_KEY_ID" => "KEY1234567", "APNS_TEAM_ID" => "TEAM123456" }.freeze

  def with_apple_env
    saved = ENV_VARS.keys.to_h { |k| [ k, ENV[k] ] }
    ENV_VARS.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  test "the client secret is a short-lived ES256 JWT for our app, signed with the key" do
    with_apple_env do
      claims, header = JWT.decode(AppleSignInTokens.client_secret, KEY, true, algorithm: "ES256")
      assert_equal "KEY1234567", header["kid"]
      assert_equal "TEAM123456", claims["iss"]
      assert_equal "com.brethreign.app", claims["sub"]
      assert_equal "https://appleid.apple.com", claims["aud"]
      assert_operator claims["exp"] - claims["iat"], :<=, 300
    end
  end

  test "does nothing without the key" do
    saved = ENV["APNS_KEY"]
    ENV["APNS_KEY"] = nil
    assert_nil AppleSignInTokens.exchange("code")
    assert_not AppleSignInTokens.revoke("token")
  ensure
    ENV["APNS_KEY"] = saved
  end
end
