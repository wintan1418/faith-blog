# frozen_string_literal: true

require "application_system_test_case"

# LinkedIn-style "New posts": someone posts while you're reading the feed, a
# pill with their face appears; tapping it brings their post to the top.
class FeedNewPostsPillTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
             tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }
    @me = create_member("pill_me", **seen)
    @friend = create_member("pill_friend", **seen)
    @room = Room.create!(name: "Pill Room", description: "x", room_type: :general, is_public: true)
    Post.create!(user: @friend, room: @room, title: "An older word", content: "Yesterday's breath",
                 status: :published, moderation_status: :approved, published_at: 1.day.ago)
    login_as @me, scope: :user
  end

  teardown { Warden.test_reset! }

  test "a post published while viewing shows the pill; tapping it reveals the post" do
    visit feed_path
    assert_selector ".fc-breath-title", text: "An older word"
    assert_selector "turbo-cable-stream-source[connected]", minimum: 1, visible: false
    assert_no_selector ".fc-new-posts-pill", visible: true

    Post.create!(user: @friend, room: @room, title: "Fresh off the press", content: "Just now",
                 status: :published, moderation_status: :approved)

    assert_selector ".fc-new-posts-pill", visible: true, text: "1 new post", wait: 5
    assert_selector ".fc-new-posts-pill .fc-pill-face", count: 1
    assert_no_selector ".fc-breath-title", text: "Fresh off the press"

    find(".fc-new-posts-pill").click

    assert_selector "#feed_list .fc-breath-title", text: "Fresh off the press", wait: 5
    assert_equal "Fresh off the press", first("#feed_list .fc-breath-title").text.strip
    assert_selector ".fc-new-dot", text: "New"
    assert_no_selector ".fc-new-posts-pill", visible: true
  end
end
