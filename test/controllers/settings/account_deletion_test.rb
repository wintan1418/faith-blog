# frozen_string_literal: true

require "test_helper"

class Settings::AccountDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      username: "leaving_#{SecureRandom.hex(3)}",
      email: "leaving_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    sign_in @user
  end

  test "shows the confirmation screen" do
    get delete_settings_account_path
    assert_response :success
    assert_match "Type your username", response.body
  end

  test "a wrong username keeps the account" do
    assert_no_difference -> { User.count } do
      delete settings_account_path, params: { confirm_username: "someone-else" }
    end
    assert_response :unprocessable_entity
  end

  test "the right username deletes the account and signs out" do
    assert_difference -> { User.count }, -1 do
      delete settings_account_path, params: { confirm_username: " #{@user.username.upcase} " }
    end
    assert_redirected_to root_path

    get feed_path
    assert_redirected_to new_user_session_path
  end

  test "signed-out visitors cannot reach the delete screen" do
    sign_out @user
    get delete_settings_account_path
    assert_redirected_to new_user_session_path
  end
end
