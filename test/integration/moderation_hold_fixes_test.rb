# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Production bugs: every breath sat "held for moderator review" and the admin
# board showed nothing to approve. Root causes covered here:
#   - a held decision wrote a review whose status didn't show on the queue
#   - a review-row validation failure wedged the post before the decision
#   - held posts with no review row were invisible everywhere in admin
#   - a signed-out author following an email link dead-ended on the placeholder
class ModerationHoldFixesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"

    @admin = User.create!(username: "mod_admin", email: "mod_admin@example.com",
                          password: "password123", password_confirmation: "password123",
                          role: :admin)
    @author = User.create!(username: "mod_author", email: "mod_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Mod Room", description: "x")
  end

  teardown do
    ENV.delete("AI_MODERATION_STUB")
  end

  def held_post!
    Post.create!(user: @author, room: @room, title: "Held breath", content: "Body",
                 status: :published, moderation_status: :pending_review)
  end

  def result_with(action:, severity:, safe: false)
    Ai::Moderation::Result.new(
      safe: safe, severity: severity, categories: [ "spam" ], score: 0.6,
      summary: "stubbed", recommended_action: action, raw_response: { "stub" => true },
      model: "stub"
    )
  end

  test "a new breath is live immediately — publish first, moderate async" do
    sign_in @author
    assert_enqueued_with(job: AiModerationGateJob) do
      post posts_path, params: { post: { content: "Grace and peace this morning.",
                                         room_id: @room.id, status: "published" } }
    end

    created = Post.order(:created_at).last
    assert created.moderation_approved?, "a fresh breath must be born approved, not held"
    assert created.feed_visible?, "a fresh breath must be on the feed right away"
  end

  test "the gate retro-holds a live post when the AI flags it" do
    post_record = Post.create!(user: @author, room: @room, title: "Live breath", content: "Body",
                               status: :published, moderation_status: :approved)

    Ai::Moderation::Reviewer.stub :call, result_with(action: "require_review", severity: "medium") do
      Ai::Moderation::RiskScorer.stub :call, nil do
        AiModerationGateJob.perform_now(post_record.id)
      end
    end

    assert post_record.reload.moderation_pending_review?, "flagged live post must be pulled for review"
    assert_equal "pending", post_record.ai_moderation_review.status
  end

  test "the gate never re-litigates a settled review" do
    post_record = Post.create!(user: @author, room: @room, title: "Settled breath", content: "Body",
                               status: :published, moderation_status: :approved)
    AiModerationReview.from_result(reviewable: post_record, user: @author,
                                   result: result_with(action: "allow", severity: "none", safe: true))

    never_called = ->(**) { flunk "Reviewer must not run for a settled post" }
    Ai::Moderation::Reviewer.stub :call, never_called do
      AiModerationGateJob.perform_now(post_record.id)
    end

    assert post_record.reload.moderation_approved?
  end

  test "a held decision writes a pending review that shows on the admin queue" do
    post_record = held_post!

    Ai::Moderation::Reviewer.stub :call, result_with(action: "require_review", severity: "medium") do
      Ai::Moderation::RiskScorer.stub :call, nil do
        AiModerationGateJob.perform_now(post_record.id)
      end
    end

    assert post_record.reload.moderation_pending_review?, "post should stay held"
    review = AiModerationReview.find_by(reviewable: post_record)
    assert_equal "pending", review.status, "held post's review must land in the default admin queue"

    sign_in @admin
    get admin_moderation_reviews_path
    assert_response :success
    assert_match @author.username, response.body
  end

  test "a review-row failure cannot wedge the post in pending_review" do
    post_record = held_post!
    raiser = ->(**) { raise ActiveRecord::RecordInvalid.new(AiModerationReview.new) }

    Ai::Moderation::Reviewer.stub :call, result_with(action: "allow", severity: "none", safe: true) do
      Ai::Moderation::RiskScorer.stub :call, nil do
        AiModerationReview.stub :from_result, raiser do
          AiModerationGateJob.perform_now(post_record.id)
        end
      end
    end

    assert post_record.reload.moderation_approved?, "decision must apply even when the audit row fails"
  end

  test "suggest_edit with severity none is released, not held" do
    Ai::Moderation::Reviewer.stub :call, result_with(action: "suggest_edit", severity: "none", safe: true) do
      verdict = Ai::Moderation::PostGatekeeper.call(post: held_post!)
      assert verdict.allow?, "expected :allow, got #{verdict.decision}"
    end
  end

  test "reviewer normalizes off-schema severity and action values" do
    raw = { "content" => [ { "type" => "text", "text" => {
      safe: false, severity: "None", categories: [], score: 0.5,
      summary: "s", recommended_action: "REVIEW"
    }.to_json } ] }

    Ai::Moderation::Client.stub :call, raw do
      result = Ai::Moderation::Reviewer.call(content: "x")
      assert_equal "none", result.severity
      assert_equal "require_review", result.recommended_action
      assert_equal "unknown", result.model
    end
  end

  test "a stuck held post with no review appears on the admin board and can be released" do
    post_record = held_post!

    sign_in @admin
    get admin_moderation_reviews_path
    assert_response :success
    assert_match "Held breaths with no review yet", response.body
    assert_match "Held breath", response.body

    post release_post_admin_moderation_reviews_path(post_id: post_record.id)
    assert_redirected_to admin_moderation_reviews_path
    assert post_record.reload.moderation_approved?, "release must approve the post"
  end

  test "a signed-out visitor to a held post is sent to sign in, and the author sees it once signed in" do
    post_record = held_post!

    get post_path(post_record)
    assert_redirected_to new_user_session_path

    sign_in @author
    get post_path(post_record)
    assert_response :success
    assert_match "Held breath", response.body
  end
end
