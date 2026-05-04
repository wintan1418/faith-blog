# frozen_string_literal: true

require "test_helper"

class PostInteractionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      username: "interaction_user",
      email: "interaction-user@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @room = Room.create!(
      name: "Interaction Room",
      description: "A room for interaction tests",
      is_public: true
    )
    @post = Post.create!(
      user: @user,
      room: @room,
      title: "Interaction test post",
      content: "A post used to verify reactions, comments, and bookmarks.",
      status: :published,
      published_at: Time.current
    )

    sign_in @user
  end

  test "post reactions update counter and return matching turbo stream" do
    post likes_path(likeable_type: "Post", likeable_id: @post.id),
         params: { reaction_type: "praying" },
         as: :turbo_stream

    assert_response :success
    assert_equal 1, @post.reload.likes_count
    assert_includes response.body, dom_id(@post, :reactions)
  end

  test "bookmarks save and return matching turbo stream" do
    post post_bookmark_path(@post), as: :turbo_stream

    assert_response :success
    assert @user.bookmarks.exists?(post: @post)
    assert_includes response.body, dom_id(@post, :bookmark)
  end

  test "comments update counter and comments stream" do
    post post_comments_path(@post),
         params: { comment: { content: "This works." } },
         as: :turbo_stream

    assert_response :success
    assert_equal 1, @post.reload.comments_count
    assert_includes response.body, dom_id(@post, :comments_list)
    assert_includes response.body, dom_id(@post, :comments_heading)
  end
end
