# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Sign in with Apple from the iPhone app: the app posts Apple's identity token
# and Rails signs the person in (making an account the first time).
class NativeAppleSessionsTest < ActionDispatch::IntegrationTest
  KEY = OpenSSL::PKey::RSA.generate(2048)
  JWK = JWT::JWK.new(KEY, kid: "test-key")
  IPHONE_UA = "Brethreign/1.0.9; NativeShare; NativeDownloads; NativeAppleSignIn; Hotwire Native iOS; Turbo Native iOS"

  def token(sub: "001234.abc", email: "grace@privaterelay.appleid.com", aud: "com.brethreign.app", exp: 10.minutes.from_now, key: JWK)
    claims = { iss: "https://appleid.apple.com", aud: aud, sub: sub, email: email, email_verified: "true",
               iat: Time.now.to_i, exp: exp.to_i }
    JWT.encode(claims, key.signing_key, "RS256", kid: key.kid)
  end

  def with_apple_keys(&block)
    AppleIdentityToken.stub(:jwks, ->(_opts = {}) { JWT::JWK::Set.new(keys: [ JWK.export ]) }, &block)
  end

  test "the first sign in makes an account, later ones find it" do
    with_apple_keys do
      assert_difference -> { User.count }, 1 do
        post native_apple_sign_in_path, params: { identity_token: token, given_name: "Grace", family_name: "Okafor" }, as: :json
      end
      assert_response :success
      user = User.find_by(provider: "apple", uid: "001234.abc")
      assert_equal "grace@privaterelay.appleid.com", user.email
      assert_match(/grace/i, user.username)
      assert response.parsed_body["location"].present?

      delete destroy_user_session_path
      # Apple can leave the email out after the first time: the Apple ID is enough.
      assert_no_difference -> { User.count } do
        post native_apple_sign_in_path, params: { identity_token: token(email: nil) }, as: :json
      end
      assert_response :success
    end
  end

  test "an existing account with the same email is used" do
    user = User.create!(email: "member@example.com", username: "member_apple", password: "password123")
    with_apple_keys do
      post native_apple_sign_in_path, params: { identity_token: token(email: "member@example.com") }, as: :json
    end
    assert_response :success
    assert_equal "apple", user.reload.provider
  end

  test "tokens for another app, expired, or not signed by Apple are refused" do
    other_key = JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "test-key")
    with_apple_keys do
      [ token(aud: "com.example.other"), token(exp: 1.minute.ago), token(key: other_key) ].each do |bad|
        assert_no_difference -> { User.count } do
          post native_apple_sign_in_path, params: { identity_token: bad }, as: :json
        end
        assert_response :unauthorized
        assert_equal new_user_session_path, response.parsed_body["location"]
      end
    end
  end

  test "the Apple button shows only in iPhone app builds that support it" do
    get new_user_session_path, headers: { "User-Agent" => IPHONE_UA }
    assert_select "a.apple-auth-button[href='#{native_apple_start_path}']", text: /Continue with Apple/

    get new_user_session_path
    assert_select "a.apple-auth-button", count: 0
  end

  test "keeps Apple's refresh token, and deleting the account revokes it" do
    with_apple_keys do
      AppleSignInTokens.stub(:exchange, ->(code) { code == "one-time" ? "r.refresh" : nil }) do
        post native_apple_sign_in_path, params: { identity_token: token, authorization_code: "one-time" }, as: :json
      end
    end
    user = User.find_by(provider: "apple", uid: "001234.abc")
    assert_equal "r.refresh", user.apple_refresh_token

    assert_enqueued_with(job: AppleTokenRevokeJob, args: [ "r.refresh" ]) do
      delete settings_account_path, params: { confirm_username: user.username }
    end
    assert_not User.exists?(user.id)
  end

  test "sign-in still works when Apple won't swap the code" do
    with_apple_keys do
      AppleSignInTokens.stub(:exchange, ->(_) { raise AppleSignInTokens::Error, "invalid_grant" }) do
        post native_apple_sign_in_path, params: { identity_token: token, authorization_code: "bad" }, as: :json
      end
    end
    assert_response :success
  end
end
