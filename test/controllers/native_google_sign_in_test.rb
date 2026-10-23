# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Google sign-in from the mobile apps: the app gets an ID token from the phone's
# Google account picker and posts it here from inside the web view.
class NativeGoogleSignInTest < ActionDispatch::IntegrationTest
  APP_USER_AGENT = "Brethreign NativeGoogleSignIn; Hotwire Native Android; Turbo Native Android"
  OLD_APP_USER_AGENT = "Hotwire Native Android; Turbo Native Android"

  setup do
    @previous_client_id = ENV["GOOGLE_CLIENT_ID"]
    ENV["GOOGLE_CLIENT_ID"] = "web-client.apps.googleusercontent.com"
  end

  teardown { ENV["GOOGLE_CLIENT_ID"] = @previous_client_id }

  def payload(overrides = {})
    { "sub" => "google-uid-123", "email" => "Faithful@Example.com", "email_verified" => true,
      "name" => "Faithful Servant" }.merge(overrides)
  end

  def post_token(result)
    verify = ->(token, aud:) {
      assert_equal "a-real-token", token
      assert_includes aud, "web-client.apps.googleusercontent.com"
      raise result if result.is_a?(Class)
      result
    }
    Google::Auth::IDTokens.stub(:verify_oidc, verify) do
      post native_google_sign_in_path, params: { id_token: "a-real-token" }, as: :json,
                                       headers: { "User-Agent" => APP_USER_AGENT }
    end
  end

  test "a verified Google account signs in and creates the member" do
    assert_difference -> { User.count }, 1 do
      post_token(payload)
    end

    assert_response :success
    assert_equal feed_path, response.parsed_body["location"]
    user = User.find_by(email: "faithful@example.com")
    assert_equal [ "google_oauth2", "google-uid-123" ], [ user.provider, user.uid ]

    get me_path, headers: { "User-Agent" => APP_USER_AGENT }
    assert_redirected_to %r{#{user.username}}
  end

  test "an existing member with the same email is signed in, not duplicated" do
    User.create!(username: "faithful", email: "faithful@example.com",
                 password: "password123", password_confirmation: "password123")

    assert_no_difference -> { User.count } do
      post_token(payload)
    end
    assert_response :success
  end

  test "an invalid token is refused" do
    post_token(Google::Auth::IDTokens::SignatureError)

    assert_response :unauthorized
    assert_equal new_user_session_path, response.parsed_body["location"]
    assert_nil User.find_by(email: "faithful@example.com")
  end

  test "an unverified Google email is refused" do
    post_token(payload("email_verified" => false))

    assert_response :unauthorized
  end

  test "the sign-in page shows the native Google button only to app versions that support it" do
    get new_user_session_path, headers: { "User-Agent" => APP_USER_AGENT }
    assert_select "a.google-auth-button[href=?]", native_google_start_path

    get new_user_session_path, headers: { "User-Agent" => OLD_APP_USER_AGENT }
    assert_select ".google-auth-button", count: 0
  end

  test "an old app that follows the link lands back on sign-in" do
    get native_google_start_path

    assert_redirected_to new_user_session_path
  end
end
