# frozen_string_literal: true

require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      username: "pusher",
      email: "pusher@example.com",
      password: "Password!1",
      password_confirmation: "Password!1"
    )
  end

  test "requires endpoint, p256dh_key, auth_key" do
    sub = PushSubscription.new(user: @user)
    refute sub.valid?
    %w[endpoint p256dh_key auth_key].each { |attr| assert sub.errors[attr].any?, "expected error on #{attr}" }
  end

  test "endpoint must be unique" do
    PushSubscription.create!(user: @user, endpoint: "https://push.example/abc", p256dh_key: "a", auth_key: "b")
    dupe = PushSubscription.new(user: @user, endpoint: "https://push.example/abc", p256dh_key: "x", auth_key: "y")
    refute dupe.valid?
    assert_includes dupe.errors[:endpoint], "has already been taken"
  end

  test "destroyed when its user is destroyed" do
    PushSubscription.create!(user: @user, endpoint: "https://push.example/zzz", p256dh_key: "a", auth_key: "b")
    assert_difference -> { PushSubscription.count }, -1 do
      @user.destroy
    end
  end
end
