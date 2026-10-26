# frozen_string_literal: true

require "test_helper"

# Feed cards: Like · Comment · Repost · Share · Save.
class PostCardActionsTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @reader = User.create!(username: "card_reader", email: "card_reader@example.com", password: test_password)
    author = User.create!(username: "card_author", email: "card_author@example.com", password: test_password)
    room = Room.create!(name: "Card Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Grace", content: "Grace and peace.", status: :published,
                         moderation_status: :approved, published_at: Time.current)
    sign_in @reader
  end

  test "cards offer Share (not Send) and Save" do
    get post_path(@post)

    assert_select "button[title=Share] .fc-action-label", text: "Share"
    assert_select "button[title=Send]", count: 0
    assert_select "#bookmark_post_#{@post.id} .fc-action-label", text: "Save"
  end

  test "saving from a card updates the button in place" do
    post post_bookmark_path(@post), as: :turbo_stream

    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="bookmark_post_#{@post.id}">}, response.body
    assert_match "Saved", response.body
  end
end
