# frozen_string_literal: true

require "test_helper"

class CommentVisibilityTest < ActiveSupport::TestCase
  setup do
    @author = User.create!(username: "cv_author", email: "cv_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @viewer = User.create!(username: "cv_viewer", email: "cv_viewer@example.com",
                           password: "password123", password_confirmation: "password123")
    @mod = User.create!(username: "cv_mod", email: "cv_mod@example.com", role: :moderator,
                        password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "CV Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: @room, title: "CV post", content: "body",
                         status: :published, moderation_status: :approved)
    @approved = @post.comments.create!(user: @author, content: "approved one",
                                       moderation_status: :approved)
    @held = @post.comments.create!(user: @author, content: "held one",
                                   moderation_status: :pending_review)
  end

  test "visible_for hides held comments from other users" do
    visible = @post.comments.visible_for(@viewer)
    assert_includes visible, @approved
    assert_not_includes visible, @held
  end

  test "visible_for shows a user their own held comment" do
    visible = @post.comments.visible_for(@author)
    assert_includes visible, @held
  end

  test "visible_for shows everything to a moderator" do
    visible = @post.comments.visible_for(@mod)
    assert_includes visible, @held
  end

  test "visible_for hides held comments from anonymous viewers" do
    visible = @post.comments.visible_for(nil)
    assert_not_includes visible, @held
  end

  test "a reply must belong to the same post as its parent comment" do
    other_post = Post.create!(user: @author, room: @room, title: "Other", content: "body",
                              status: :published, moderation_status: :approved)
    reply = other_post.comments.build(user: @viewer, content: "mismatched",
                                      parent_comment: @approved)
    assert_not reply.valid?
    assert_includes reply.errors[:parent_comment], "must belong to the same post"
  end
end
