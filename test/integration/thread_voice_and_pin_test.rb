# frozen_string_literal: true

require "test_helper"

# Engagement: commenting on a thread alerts everyone who has spoken in it,
# and admin-pinned breaths lead the feed as a community noticeboard.
class ThreadVoiceAndPinTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "tv_author", email: "tv_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @alice = User.create!(username: "tv_alice", email: "tv_alice@example.com",
                          password: "password123", password_confirmation: "password123")
    @bola = User.create!(username: "tv_bola", email: "tv_bola@example.com",
                         password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "TV Room", description: "x")
    @thread = Post.create!(user: @author, room: @room, title: "How do you keep a prayer habit?",
                           content: "Honest question for the brethren.", status: :published,
                           moderation_status: :approved, kind: :thread)
    @thread.comments.create!(user: @alice, content: "Morning walks help me pray.")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "a new comment on a thread alerts earlier voices, not the commenter or author twice" do
    sign_in @bola
    assert_difference -> { Notification.where(notification_type: :thread_new_voice).count }, 1 do
      post post_comments_path(@thread), params: { comment: { content: "Evening psalms for me." } }
    end

    voice = Notification.thread_new_voice.last
    assert_equal @alice, voice.user, "the earlier commenter gets the thread alert"
    assert_equal @bola, voice.actor
    assert_equal post_path(@thread), voice.target_path

    # The author is notified via new_comment, never doubled with a voice alert.
    author_types = Notification.where(user: @author).pluck(:notification_type)
    assert_includes author_types, "new_comment"
    assert_not_includes author_types, "thread_new_voice"
  end

  test "a comment can be lifted into a breath of its own" do
    comment = @thread.comments.create!(user: @bola, content: "Fasting taught me to hunger for the Word. <b>bold</b>")

    sign_in @alice
    get new_post_path(from_comment: comment.id)

    assert_response :success
    assert_match "A word from @tv_bola", response.body
    assert_match "Fasting taught me to hunger for the Word.", response.body
    # The thread rides along as an embedded quote so readers can trace it back.
    assert_match @thread.title, response.body
  end

  test "a deleted or invisible comment cannot be lifted" do
    comment = @thread.comments.create!(user: @bola, content: "Soon deleted.")
    comment.update!(deleted_at: Time.current)

    sign_in @alice
    get new_post_path(from_comment: comment.id)
    assert_response :success
    assert_no_match "Soon deleted.", response.body
  end

  test "pinned breaths lead the feed with the pinned strip" do
    pinned = Post.create!(user: @author, room: @room, title: "Community fast this Friday",
                          content: "Join us as we seek His face together.", status: :published,
                          moderation_status: :approved, featured: true)

    sign_in @alice
    get feed_path
    assert_response :success
    assert_match "Pinned for the community", response.body
    assert_select ".fc-pinned-card", text: /Community fast this Friday/
    # Not duplicated in the regular stream below the strip.
    assert_select "#feed_list .fc-breath-title", text: /Community fast this Friday/, count: 0
  end
end
