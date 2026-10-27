# frozen_string_literal: true

require "test_helper"

# LinkedIn-style chains: one level of replies under each comment. Replying to a
# reply joins the same chain and @mentions the person it answers.
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
    @reply = @post.comments.create!(user: @ada, content: "First reply", parent_comment: @top)
  end

  test "replying to a reply joins the chain and mentions the person" do
    sign_in @ben
    post reply_post_comment_path(@post, @reply), params: { comment: { content: "Amen to that" } }

    answer = Comment.order(:id).last
    assert_equal @top, answer.parent_comment
    assert_equal "@ada_reply Amen to that", answer.content.to_plain_text.strip
  end

  test "replying to your own reply doesn't mention yourself" do
    sign_in @ada
    post reply_post_comment_path(@post, @reply), params: { comment: { content: "One more thing" } }

    assert_equal "One more thing", Comment.order(:id).last.content.to_plain_text.strip
  end

  test "replying to a top-level comment nests under it" do
    sign_in @ben
    post reply_post_comment_path(@post, @top), params: { comment: { content: "Thank you" } }

    answer = Comment.order(:id).last
    assert_equal @top, answer.parent_comment
    assert_equal "Thank you", answer.content.to_plain_text.strip
  end

  test "older two-level chains still show flat under the top comment" do
    old = @post.comments.create!(user: @ben, content: "Deep from before", parent_comment: @reply)
    assert_includes @top.thread_replies, old
    assert_equal @top, old.thread_root
  end

  test "the post page shows the reply count, folds older replies and has a Reply on every reply" do
    3.times { |i| @post.comments.create!(user: @ben, content: "More #{i}", parent_comment: @top) }
    sign_in @ben
    get post_path(@post)

    assert_select "##{ActionView::RecordIdentifier.dom_id(@top)} .cm-action--count", text: "4 replies"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@top)} .cm-thread-more", text: "View 2 earlier replies"
    assert_select ".cm--reply .cm-action", text: "Reply", count: 4
  end
end
