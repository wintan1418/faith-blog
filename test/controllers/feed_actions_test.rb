# frozen_string_literal: true

require "test_helper"

class FeedActionsTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(
      username: "feed_author",
      email: "feed_author@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @reader = User.create!(
      username: "feed_reader",
      email: "feed_reader@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @room = Room.create!(name: "Feed Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(
      user: @author,
      room: @room,
      title: "A breath for the feed",
      content: "Grace and peace.",
      status: :published,
      moderation_status: :approved
    )
  end

  test "feed renders the overflow menu with the secondary actions inside it" do
    sign_in @reader
    get feed_path
    assert_response :success

    # The ⋯ trigger and its menu live in the card header now.
    assert_select ".fc-breath-head .fc-breath-more [data-dropdown-target='menu'].fc-breath-menu" do
      # Save / report live inside the menu, not loose in the action bar.
      assert_select "form[action=?]", post_bookmark_path(@post)
      assert_select "form[action=?]", reports_path
    end

    # And they are not rendered inside the action bar.
    assert_select ".fc-breath-actions form[action=?]", post_bookmark_path(@post), false
  end

  test "feed shows the reaction summary strip and a single React button" do
    sign_in @reader
    get feed_path
    assert_response :success

    # Engagement meta row lives above the bar; the bar holds the Like segment.
    assert_select "##{ActionView::RecordIdentifier.dom_id(@post, :reaction_summary)}.fc-breath-stats"
    assert_select ".fc-breath-actions .fc-reactions .fc-react-btn .fc-react-label", text: "Like"
    # Comment / repost / send are present as their own labelled segments.
    assert_select ".fc-breath-actions .fc-repost"
    assert_select ".fc-breath-actions .fc-share .fc-action-label", text: "Send"
  end

  test "reacting updates both the React button and the summary strip" do
    sign_in @reader
    post likes_path(likeable_type: "Post", likeable_id: @post.id, reaction_emoji: "🙏"),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    summary_id = ActionView::RecordIdentifier.dom_id(@post, :reaction_summary)
    reactions_id = ActionView::RecordIdentifier.dom_id(@post, :reactions)
    assert_select "turbo-stream[action='replace'][target='#{summary_id}']"
    assert_select "turbo-stream[action='replace'][target='#{reactions_id}']"
  end
end
