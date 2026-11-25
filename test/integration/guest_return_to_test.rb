require "test_helper"

# After the "join to continue" dialog, a visitor lands back on the page they tapped.
class GuestReturnToTest < ActionDispatch::IntegrationTest
  test "signing up from the dialog returns to the tapped page" do
    get new_user_registration_path(return_to: "/posts/abc?ref=feed")
    post user_registration_path, params: { user: { username: "returner", email: "returner@example.com", password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    # "Check your email" first; verifying (or "Do this later") goes on to the tapped page.
    assert_redirected_to email_verification_path(return_to: "/posts/abc?ref=feed")
    follow_redirect!
    assert_select "a[href=?]", "/posts/abc?ref=feed", text: "Do this later"
  end

  test "signing in from the dialog returns to the tapped page" do
    password = SecureRandom.base58(16)
    user = User.create!(username: "comeback", email: "comeback@example.com", password: password)
    user.confirm if user.respond_to?(:confirm)
    get new_user_session_path(return_to: "/rooms")
    post user_session_path, params: { user: { email: user.email, password: password } }
    assert_redirected_to "/rooms"
  end

  test "without return_to a new member still lands on the feed" do
    post user_registration_path, params: { user: { username: "plainjoin", email: "plainjoin@example.com", password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    assert_redirected_to email_verification_path
    follow_redirect!
    assert_select "a[href=?]", feed_path, text: "Do this later"
  end

  test "unsafe or pointless return_to values are ignored" do
    [ "//evil.example/x", "https://evil.example/x", "/\\evil.example", "/users/sign_in", "/auth/google", "/", "/?browse=1", "javascript:alert(1)", "posts/1", "/#{'a' * 600}" ].each do |bad|
      assert_nil GuestReturnTo.safe_path(bad), "should reject #{bad.inspect}"
    end
    assert_equal "/posts/1", GuestReturnTo.safe_path("/posts/1")
    assert_equal "/u/someone?tab=about", GuestReturnTo.safe_path("/u/someone?tab=about")
  end

  test "an unsafe return_to does not change where sign-up lands" do
    get new_user_registration_path(return_to: "//evil.example/steal")
    post user_registration_path, params: { user: { username: "safejoin", email: "safejoin@example.com", password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    assert_redirected_to email_verification_path
  end

  test "the apps still land on the feed" do
    get new_user_registration_path(return_to: "/rooms"), headers: { "User-Agent" => "Hotwire Native Android" }
    post user_registration_path, params: { user: { username: "appjoin", email: "appjoin@example.com", password: SecureRandom.base58(16) } }.merge(human_signup_fields),
      headers: { "User-Agent" => "Hotwire Native Android" }
    assert_redirected_to feed_path
  end
end
