# frozen_string_literal: true

require "test_helper"

# The redesigned sign in / join pages.
class AuthPagesTest < ActionDispatch::IntegrationTest
  # Generated per run so no password-looking literal sits in the repo (secret scanners flag them).
  setup { @password = test_password }

  test "sign in page has the breathing mark, fields and show-password toggle" do
    get new_user_session_path

    assert_response :success
    assert_select ".auth .auth-breath"
    assert_select "input#user_email[type=email][required]"
    assert_select "[data-controller=password-field] button.auth-eye"
    assert_select "a[href=?]", new_user_registration_path
  end

  test "joining needs no password confirmation field" do
    get new_user_registration_path
    assert_select "input#user_password_confirmation", count: 0

    assert_difference -> { User.count }, 1 do
      post user_registration_path, params: { user: { username: "new_breather", email: "new_breather@example.com", password: @password } }
    end
  end

  test "sign in still works" do
    User.create!(username: "returning", email: "returning@example.com", password: @password, password_confirmation: @password)
    post user_session_path, params: { user: { email: "returning@example.com", password: @password } }

    assert_response :redirect
    follow_redirect!
    assert_response :success
  end
end
