# frozen_string_literal: true

require "test_helper"

# LinkedIn-style chains: you can reply to any reply; past two levels the reply
# joins that level and @mentions the person it answers.
class DeepRepliesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_reply", email: "ada-reply@example.com", password: pass, password_confirmation: pass)
    @ben = User.create!(username: "ben_reply", email: "ben-reply@example.com", password: pass, password_confirmation: pass)
    room = Room.create!(name: "Replies Room", description: "x", is_public: true)
    @post = Post.create!(user: @ada, room: room, title: "Reply chains", content: "Testing reply chains.",
                         status: :published, published_at: Time.current)
    @top = @post.comments.create!(user: @ada, content: "Top comment")
    @level1 = @post.comments.create!(user: @ben, content: "First reply", parent_comment: @top)
    @level2 = @post.comments.create!(user: @ada, content: "Reply to the reply", parent_comment: @level1)
  end

  test "a reply to a deep reply joins that level and mentions the person" do
    sign_in @ben
    post reply_post_comment_path(@post, @level2), params: { comment: { content: "Amen to that" } }

    reply = Comment.order(:id).last
    assert_equal @level1, reply.parent_comment
    assert_equal Comment::MAX_DEPTH, reply.depth
    assert_equal "@ada_reply Amen to that", reply.content.to_plain_text.strip
  end

  test "a reply one level down nests as usual" do
    sign_in @ada
    post reply_post_comment_path(@post, @level1), params: { comment: { content: "Thank you" } }

    reply = Comment.order(:id).last
    assert_equal @level1, reply.parent_comment
    assert_equal "Thank you", reply.content.to_plain_text.strip
  end

  test "deep replies show a Reply button" do
    sign_in @ben
    get post_path(@post)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@level2)} .fc-comment-actions", text: /Reply/
  end
end
