# frozen_string_literal: true

require "test_helper"

class PostHeldForReviewTest < ActiveSupport::TestCase
  setup { ENV["AI_MODERATION_STUB"] = "1" }

  def make_user(role: nil)
    suffix = SecureRandom.hex(3)
    User.create!(
      username: "u_#{suffix}",
      email: "u_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: role || :member
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

  def review_with(post:, severity:, status:)
    AiModerationReview.create!(
      reviewable: post,
      user: post.user,
      status: status,
      severity: severity,
      recommended_action: "hide_pending_review",
      categories: [],
      score: 0.9,
      summary: "x",
      model: "stub",
      raw_response: {},
      reviewed_at: Time.current
    )
  end

  test "post with no review is not held" do
    refute make_post(make_user).held_for_review?
  end

  test "high severity flagged review marks the post as held" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :flagged)
    assert post.reload.held_for_review?
  end

  test "high severity dismissed review unholds the post" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :dismissed)
    refute post.reload.held_for_review?
  end

  test "medium severity is never held automatically" do
    post = make_post(make_user)
    review_with(post: post, severity: "medium", status: :flagged)
    refute post.reload.held_for_review?
  end

  test "author can see their own held breath" do
    user = make_user
    post = make_post(user)
    review_with(post: post, severity: "high", status: :flagged)
    assert post.visible_to?(user)
  end

  test "another member cannot see a held breath" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :flagged)
    refute post.visible_to?(make_user)
  end

  test "admin can see a held breath" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :flagged)
    assert post.visible_to?(make_user(role: :admin))
  end

  test "moderator can see a held breath" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :flagged)
    assert post.visible_to?(make_user(role: :moderator))
  end

  test "guest (nil viewer) cannot see a held breath" do
    post = make_post(make_user)
    review_with(post: post, severity: "high", status: :flagged)
    refute post.visible_to?(nil)
  end
end
