# frozen_string_literal: true

require "test_helper"

class AiModerationReviewTest < ActiveSupport::TestCase
  def make_user(suffix = SecureRandom.hex(4))
    User.create!(
      username: "user_#{suffix}",
      email: "user_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_room
    Room.create!(name: "Room #{SecureRandom.hex(4)}", description: "x")
  end

  def make_post(author = make_user)
    Post.create!(
      user: author,
      room: make_room,
      title: "Test post #{SecureRandom.hex(4)}",
      content: "Body of the test post.",
      status: :published
    )
  end

  test "from_result creates a flagged review from an unsafe Result" do
    user = make_user
    post = make_post(user)

    result = Ai::Moderation::Result.new(
      safe: false,
      severity: "high",
      categories: [ "violence" ],
      score: 0.92,
      summary: "Threat",
      recommended_action: "hide_pending_review",
      raw_response: { "stub" => true },
      model: "stub"
    )

    review = AiModerationReview.from_result(reviewable: post, user: user, result: result)

    assert review.persisted?
    assert review.flagged?
    assert_equal "high", review.severity
    assert_includes review.categories, "violence"
    assert_in_delta 0.92, review.score
    assert_equal "hide_pending_review", review.recommended_action
    assert review.reviewed_at.present?
  end

  test "from_result updates an existing review for the same reviewable" do
    user = make_user
    post = make_post(user)

    safe_result = Ai::Moderation::Result.new(
      safe: true, severity: "none", categories: [], score: 0.05,
      summary: "fine", recommended_action: "allow",
      raw_response: {}, model: "stub"
    )
    AiModerationReview.from_result(reviewable: post, user: user, result: safe_result)

    flagged_result = Ai::Moderation::Result.new(
      safe: false, severity: "medium", categories: [ "harassment" ], score: 0.6,
      summary: "rude", recommended_action: "require_review",
      raw_response: {}, model: "stub"
    )

    assert_no_difference -> { AiModerationReview.count } do
      AiModerationReview.from_result(reviewable: post, user: user, result: flagged_result)
    end

    review = post.reload.ai_moderation_review
    assert review.flagged?
    assert_equal "medium", review.severity
    assert_includes review.categories, "harassment"
  end

  test "needs_attention scope returns pending and flagged" do
    user = make_user
    post = make_post(user)
    other_post = make_post(user)

    flagged = Ai::Moderation::Result.new(
      safe: false, severity: "medium", categories: [ "spam" ], score: 0.6,
      summary: "x", recommended_action: "require_review",
      raw_response: {}, model: "stub"
    )
    safe = Ai::Moderation::Result.new(
      safe: true, severity: "none", categories: [], score: 0.0,
      summary: "ok", recommended_action: "allow",
      raw_response: {}, model: "stub"
    )

    flagged_review = AiModerationReview.from_result(reviewable: post, user: user, result: flagged)
    AiModerationReview.from_result(reviewable: other_post, user: user, result: safe)

    ids = AiModerationReview.needs_attention.pluck(:id)
    assert_includes ids, flagged_review.id
  end
end
