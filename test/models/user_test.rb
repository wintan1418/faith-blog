# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "creates user from google auth payload" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-123",
      info: {
        email: "abbie@example.com",
        name: "Abbie Faith"
      }
    )

    user = User.from_google(auth)

    assert user.persisted?
    assert_equal "abbie@example.com", user.email
    assert_equal "google_oauth2", user.provider
    assert_equal "google-123", user.uid
    assert_equal "abbie_faith", user.username
    assert user.profile.present?
    assert user.brethren_card.present?
  end

  test "links google auth to existing email user" do
    user = User.create!(
      username: "abbie",
      email: "abbie@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-456",
      info: {
        email: "abbie@example.com",
        name: "Different Name"
      }
    )

    assert_no_difference("User.count") do
      assert_equal user, User.from_google(auth)
    end

    assert_equal "google_oauth2", user.reload.provider
    assert_equal "google-456", user.uid
  end
end
