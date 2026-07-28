# frozen_string_literal: true

require "test_helper"

# The Wall of Answered Prayers (/answered) — public celebration page.
class AnsweredPrayersWallTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "wall_author", email: "wall@example.com",
                           password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Wall Room", description: "x")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "shows answered prayers with chain stats, publicly" do
    post = Post.create!(user: @author, room: @room, title: "Healing for mum",
                        content: "Please stand with me", status: :published,
                        moderation_status: :approved, published_at: 10.days.ago,
                        prayer_status: :prayer_answered, prayer_answered_at: 1.day.ago)
    intercessor = User.create!(username: "wall_prayer", email: "wallp@example.com",
                               password: "password123", password_confirmation: "password123")
    PrayerIntercession.create!(user: intercessor, post: post)

    get answered_prayers_path
    assert_response :success
    assert_match "Wall of Answered Prayers", response.body
    assert_match "Healing for mum", response.body
    assert_match "in the chain", response.body
    assert_match "Carried for", response.body
  end

  test "anonymous answered prayers do not leak the author" do
    Post.create!(user: @author, room: @room, title: "Secret burden",
                 content: "Anon need", status: :published, anonymous: true,
                 moderation_status: :approved, published_at: 5.days.ago,
                 prayer_status: :prayer_answered, prayer_answered_at: 2.days.ago)

    get answered_prayers_path
    assert_response :success
    assert_match "Anonymous", response.body
    assert_no_match(/wall_author/, response.body)
  end

  test "pending prayers stay off the wall" do
    Post.create!(user: @author, room: @room, title: "Still praying",
                 content: "Not yet", status: :published,
                 moderation_status: :approved, published_at: 2.days.ago,
                 prayer_status: :prayer_pending)

    get answered_prayers_path
    assert_response :success
    assert_no_match(/Still praying/, response.body)
    assert_match "waiting for its first testimony", response.body
  end
end
