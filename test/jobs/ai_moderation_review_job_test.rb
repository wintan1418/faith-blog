# frozen_string_literal: true

require "test_helper"

class AiModerationReviewJobTest < ActiveJob::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    ENV["ANTHROPIC_API_KEY"] = nil
  end

  def make_user
    User.create!(
      username: "u_#{SecureRandom.hex(4)}",
      email: "u_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_room
    Room.create!(name: "Room #{SecureRandom.hex(4)}", description: "x")
  end

  def make_post(author:, title: "A clean post", body: "Praying for you all.", status: :published)
    Post.create!(
      user: author,
      room: make_room,
      title: title,
      content: body,
      status: status
    )
  end

  test "publishing a post enqueues the moderation gate" do
    user = make_user
    # Publish-first flow: posts go live at create and the GATE job (classify +
    # enforce) runs behind them, not the audit-only review job.
    assert_enqueued_with(job: AiModerationGateJob) do
      make_post(author: user)
    end
  end

  test "draft posts do NOT enqueue a review" do
    user = make_user
    assert_no_enqueued_jobs(only: AiModerationGateJob) do
      make_post(author: user, status: :draft)
    end
  end

  test "performing the job persists a cleared review for benign content" do
    user = make_user
    post = nil
    perform_enqueued_jobs do
      post = make_post(author: user, body: "Praying for everyone going through hardship.")
    end

    review = post.reload.ai_moderation_review
    assert review.present?
    assert review.cleared?
    assert_equal "none", review.severity
  end

  test "flagged content writes a flagged review and elevates risk_profile to watch" do
    user = make_user
    post = nil
    perform_enqueued_jobs do
      post = make_post(author: user, title: "Bad post", body: "I will kill that person.")
    end

    review = post.reload.ai_moderation_review
    assert review.flagged?
    assert_equal "high", review.severity
    assert_includes review.categories, "violence"

    assert_equal "watch", user.reload.risk_profile.risk_level
    assert_equal 1, user.risk_profile.flagged_reviews_count
  end

  test "comment creation enqueues a review" do
    user = make_user
    post = make_post(author: user)
    perform_enqueued_jobs # drain post review

    assert_enqueued_with(job: AiModerationReviewJob) do
      Comment.create!(user: user, post: post, content: "First comment.")
    end
  end
end
