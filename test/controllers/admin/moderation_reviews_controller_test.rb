# frozen_string_literal: true

require "test_helper"

class Admin::ModerationReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    ENV["ANTHROPIC_API_KEY"] = nil

    @admin = User.create!(
      username: "admin_#{SecureRandom.hex(3)}",
      email: "admin_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :admin
    )

    @author = User.create!(
      username: "author_#{SecureRandom.hex(3)}",
      email: "author_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    @room = Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x")
    @post = Post.create!(user: @author, room: @room, title: "Title", content: "Body", status: :published)

    flagged = Ai::Moderation::Result.new(
      safe: false, severity: "high", categories: [ "violence" ], score: 0.92,
      summary: "Threat", recommended_action: "hide_pending_review",
      raw_response: { "stub" => true }, model: "stub"
    )
    @review = AiModerationReview.from_result(reviewable: @post, user: @author, result: flagged)
  end

  test "non-admin cannot reach the queue" do
    sign_in @author
    get admin_moderation_reviews_path
    assert_redirected_to root_path
  end

  test "admin sees the queue with the flagged review" do
    sign_in @admin
    get admin_moderation_reviews_path
    assert_response :success
    assert_match @author.username, @response.body
    assert_match "high", @response.body
  end

  test "admin can view a single review" do
    sign_in @admin
    get admin_moderation_review_path(@review)
    assert_response :success
    assert_match @post.title, @response.body
    assert_match @review.summary, @response.body
  end

  test "decide=dismiss marks the review dismissed and writes a moderation log" do
    sign_in @admin
    assert_difference -> { ModerationLog.count }, 1 do
      post decide_admin_moderation_review_path(@review), params: { decision: "dismiss", notes: "false positive" }
    end
    assert_redirected_to admin_moderation_reviews_path
    assert_equal "dismissed", @review.reload.status
    assert_equal "ai_review_dismiss", ModerationLog.last.action
    assert_equal @review.id, ModerationLog.last.ai_moderation_review_id
  end

  test "decide=suspend marks review actioned and elevates user risk to suspended" do
    sign_in @admin
    post decide_admin_moderation_review_path(@review), params: { decision: "suspend", notes: "" }
    assert_equal "actioned", @review.reload.status
    assert_equal "suspended", @author.reload.risk_profile.risk_level
  end

  test "suspend against a staff member's content actions the review but never the account" do
    staff = User.create!(
      username: "staff_#{SecureRandom.hex(3)}",
      email: "staff_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: :super_admin
    )
    staff_post = Post.create!(user: staff, room: @room, title: "Staff post", content: "Body", status: :published)
    flagged = Ai::Moderation::Result.new(
      safe: false, severity: "high", categories: [ "spam" ], score: 0.9,
      summary: "Test", recommended_action: "block",
      raw_response: { "stub" => true }, model: "stub"
    )
    staff_review = AiModerationReview.from_result(reviewable: staff_post, user: staff, result: flagged)

    sign_in @admin
    post decide_admin_moderation_review_path(staff_review), params: { decision: "suspend", notes: "" }

    assert_equal "actioned", staff_review.reload.status
    assert staff.reload.active?, "a review decision must never deactivate a staff account"
    refute_equal "suspended", staff.risk_profile&.risk_level
  end

  test "unknown decision is rejected" do
    sign_in @admin
    post decide_admin_moderation_review_path(@review), params: { decision: "nuke" }
    assert_redirected_to admin_moderation_review_path(@review)
    assert_equal "flagged", @review.reload.status
  end
end
