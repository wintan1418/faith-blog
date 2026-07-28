# frozen_string_literal: true

require "test_helper"

# The activation ring on the feed: visible with per-step links while any of
# the three first steps is missing, gone once all are done.
class OnboardingRingTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @user = User.create!(username: "ring_user", email: "ring@example.com",
                         password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Ring Room", description: "x")
    sign_in @user
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "fresh account sees the ring at 0/3 with all three step links" do
    get feed_path
    assert_response :success
    assert_match "fc-onboard-ring", response.body
    assert_match "0/3", response.body
    assert_match "Brethren someone", response.body
    assert_match "Step into a room", response.body
    assert_match "Take a breath", response.body
  end

  test "completed steps show as done and the count rises" do
    other = User.create!(username: "ring_friend", email: "ringf@example.com",
                         password: "password123", password_confirmation: "password123")
    @user.active_follows.create!(following: other)
    @room.room_memberships.create!(user: @user)

    get feed_path
    assert_match "2/3", response.body
    assert_match "✓ Brethren someone", response.body
    assert_match "✓ Step into a room", response.body
  end

  test "ring disappears once all three are done" do
    other = User.create!(username: "ring_done", email: "ringd@example.com",
                         password: "password123", password_confirmation: "password123")
    @user.active_follows.create!(following: other)
    @room.room_memberships.create!(user: @user)
    Post.create!(user: @user, room: @room, title: "First breath", content: "Here",
                 status: :published, moderation_status: :approved)

    get feed_path
    assert_no_match(/fc-onboard-ring/, response.body)
  end
end
