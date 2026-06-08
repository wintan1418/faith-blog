# frozen_string_literal: true

require "test_helper"

class CommentSoftDeleteTest < ActiveSupport::TestCase
  setup { ENV["AI_MODERATION_STUB"] = "1" }

  def make_user
    suffix = SecureRandom.hex(3)
    User.create!(
      username: "u_#{suffix}",
      email: "u_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_post(user)
    Post.create!(
      user: user,
      room: Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x"),
      title: "A breath worth sharing",
      content: "Body.",
      status: :published
    )
  end

  def add_comment(post, user, parent: nil)
    post.comments.create!(user: user, content: "hello", parent_comment: parent)
  end

  test "soft_delete decrements the post's comments_count" do
    user = make_user
    post = make_post(user)
    c1 = add_comment(post, user)
    add_comment(post, user)
    assert_equal 2, post.reload.comments_count

    c1.soft_delete!

    assert_equal 1, post.reload.comments_count
    assert c1.reload.deleted?
  end

  test "soft_delete decrements the parent's replies_count" do
    user = make_user
    post = make_post(user)
    parent = add_comment(post, user)
    reply  = add_comment(post, user, parent: parent)
    assert_equal 1, parent.reload.replies_count

    reply.soft_delete!

    assert_equal 0, parent.reload.replies_count
  end

  test "soft_delete is idempotent and never drives a count below zero" do
    user = make_user
    post = make_post(user)
    comment = add_comment(post, user)
    assert_equal 1, post.reload.comments_count

    comment.soft_delete!
    comment.soft_delete! # second call must be a no-op

    assert_equal 0, post.reload.comments_count
  end
end
