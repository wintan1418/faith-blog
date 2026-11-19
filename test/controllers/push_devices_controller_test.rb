# frozen_string_literal: true

require "test_helper"

class PushDevicesControllerTest < ActionDispatch::IntegrationTest
  def make_user
    suffix = SecureRandom.hex(4)
    User.create!(username: "user_#{suffix}", email: "user_#{suffix}@example.com",
                 password: "password123", password_confirmation: "password123")
  end

  test "a signed-in app registers its token" do
    user = make_user
    sign_in user

    assert_difference -> { user.push_devices.count }, 1 do
      post push_devices_path, params: { token: "abc123", platform: "apple", name: "iPhone" }
    end
    assert_response :created
  end

  test "the same phone moves to whoever signs in next" do
    first, second = make_user, make_user
    sign_in first
    post push_devices_path, params: { token: "shared-phone", platform: "google" }
    sign_out first

    sign_in second
    assert_no_difference -> { ApplicationPushDevice.count } do
      post push_devices_path, params: { token: "shared-phone", platform: "google" }
    end
    assert_equal second, ApplicationPushDevice.find_by(token: "shared-phone").owner
  end

  test "another account can't take over a token it doesn't hold" do
    victim, thief = make_user, make_user
    ApplicationPushDevice.create!(token: "victim-phone", platform: "apple", owner: victim)

    sign_in thief
    post push_devices_path, params: { token: "victim-phone", platform: "apple" }
    assert_response :conflict
    assert_equal victim, ApplicationPushDevice.find_by(token: "victim-phone").owner
  end

  test "a token can't be deleted by someone who doesn't own it" do
    ApplicationPushDevice.create!(token: "keep-me", platform: "apple", owner: make_user)
    delete push_devices_path, params: { token: "keep-me" } # signed out, a different phone
    assert ApplicationPushDevice.exists?(token: "keep-me")

    sign_in make_user
    delete push_devices_path, params: { token: "keep-me" }
    assert ApplicationPushDevice.exists?(token: "keep-me")
  end

  test "rejects an unknown platform" do
    sign_in make_user
    post push_devices_path, params: { token: "abc", platform: "windows" }
    assert_response :unprocessable_entity
  end

  test "signed-out visitors cannot register" do
    post push_devices_path, params: { token: "abc", platform: "apple" }
    assert_response :redirect
    assert_equal 0, ApplicationPushDevice.count
  end

  test "signing out removes the device" do
    user = make_user
    sign_in user
    post push_devices_path, params: { token: "bye", platform: "apple" }
    sign_out user

    delete push_devices_path, params: { token: "bye" }
    assert_response :no_content
    assert_not ApplicationPushDevice.exists?(token: "bye")
  end

  test "deleting an account removes its devices" do
    user = make_user
    ApplicationPushDevice.create!(token: "gone", platform: "apple", owner: user)
    user.destroy!
    assert_not ApplicationPushDevice.exists?(token: "gone")
  end
end
