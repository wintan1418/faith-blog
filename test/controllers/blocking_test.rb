# frozen_string_literal: true

require "test_helper"

# Blocking someone (from a breath's ⋯ menu or their profile) hides their
# breaths, reposts and comments from you, and yours from them, and stops
# messages. App stores require this for apps where people post.
class BlockingTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @me = create_member("block_me", welcomed_at: Time.current, tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @them = create_member("block_them")
    @room = Room.create!(name: "Block Room", description: "x", room_type: :general, is_public: true)
    @their_post = Post.create!(user: @them, room: @room, title: "Their breath", content: "From the one I'll block.",
                               status: :published, moderation_status: :approved, allow_comments: true)
    @other_post = Post.create!(user: create_member("block_other"), room: @room, title: "Someone else",
                               content: "Still here.", status: :published, moderation_status: :approved, allow_comments: true)
    @their_comment = Comment.create!(user: @them, post: @other_post, content: "A comment from them", moderation_status: :approved)
    sign_in @me
  end

  test "Block is on another member's breath menu and their profile" do
    get feed_path
    assert_select ".fc-breath-menu form[action=?]", message_blocks_path(user_id: @them.id)
    get user_path(@them.username)
    assert_select ".profile-safety form[action=?]", message_blocks_path(user_id: @them.id)
  end

  test "after blocking, their breaths, reposts and comments are gone; unblocking brings them back" do
    Reshare.create!(user: @them, post: @other_post) if defined?(Reshare)

    post message_blocks_path(user_id: @them.id)
    assert_redirected_to feed_path
    follow_redirect!
    assert_match "You blocked", response.body

    get feed_path
    assert_no_match "Their breath", response.body
    assert_match "Someone else", response.body

    assert_not Comment.visible_for(@me).exists?(@their_comment.id), "their comment still shows"
    get user_path(@them.username)
    assert_select "h3", "Blocked"
    assert_no_match "Their breath", response.body

    # Works both ways: they don't see mine either.
    assert_includes @them.blocked_user_ids, @me.id

    delete message_block_path(@them)
    get feed_path
    assert_match "Their breath", response.body
    assert Comment.visible_for(User.find(@me.id)).exists?(@their_comment.id)
  end
end
