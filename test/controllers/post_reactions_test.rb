# frozen_string_literal: true

require "test_helper"

# The "who reacted" list for a breath (PostsController#reactions).
class PostReactionsTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "react_author", email: "react_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @fan = User.create!(username: "react_fan", email: "react_fan@example.com",
                        password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "React Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: @room, title: "A breath",
                         content: "Grace and peace.", status: :published,
                         moderation_status: :approved)
  end

  test "lists the people who reacted, with their emoji" do
    Like.create!(user: @fan, likeable: @post, reaction_type: :amen, reaction_emoji: "🙏")

    sign_in @author
    get reactions_post_path(@post)

    assert_response :success
    assert_select "turbo-frame#reactors_panel"
    assert_match @fan.username, response.body
    assert_match "🙏", response.body
  end

  test "shows an empty state when nobody has reacted" do
    sign_in @author
    get reactions_post_path(@post)

    assert_response :success
    assert_match(/No reactions yet/i, response.body)
  end

  test "a held post's reactions are not exposed to other users" do
    @post.update_columns(moderation_status: Post.moderation_statuses[:pending_review])

    sign_in @fan
    get reactions_post_path(@post)
    assert_response :not_found
  end

  test "the author can still see reactions on their own held post" do
    @post.update_columns(moderation_status: Post.moderation_statuses[:pending_review])

    sign_in @author
    get reactions_post_path(@post)
    assert_response :success
  end
end
