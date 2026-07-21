# frozen_string_literal: true

require "test_helper"

class ModerationBacklogSweepJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  def pending_post(user, created_at:)
    post = Post.create!(
      user: user,
      room: Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x"),
      title: "A gentle breath",
      content: "Grace and peace to you.",
      status: :published,
      moderation_status: :pending_review
    )
    post.update_columns(created_at: created_at)
    post
  end

  test "re-enqueues the gate for posts stuck past the grace period" do
    stale = pending_post(make_user, created_at: 30.minutes.ago)

    assert_enqueued_with(job: AiModerationGateJob, args: [ stale.id ]) do
      ModerationBacklogSweepJob.perform_now
    end
  end

  test "ignores posts still within the grace period" do
    pending_post(make_user, created_at: 1.minute.ago)

    assert_no_enqueued_jobs only: AiModerationGateJob do
      ModerationBacklogSweepJob.perform_now
    end
  end

  test "ignores approved posts that already have a settled review" do
    user = make_user
    post = pending_post(user, created_at: 30.minutes.ago)
    post.update_columns(moderation_status: Post.moderation_statuses[:approved])
    AiModerationReview.create!(reviewable: post, user: user, status: :cleared,
                               severity: "none", recommended_action: "allow",
                               categories: [], score: 0.0, reviewed_at: Time.current)

    assert_no_enqueued_jobs only: AiModerationGateJob do
      ModerationBacklogSweepJob.perform_now
    end
  end

  test "re-enqueues the gate for live posts that were never classified" do
    post = pending_post(make_user, created_at: 30.minutes.ago)
    post.update_columns(moderation_status: Post.moderation_statuses[:approved])

    assert_enqueued_with(job: AiModerationGateJob, args: [ post.id ]) do
      ModerationBacklogSweepJob.perform_now
    end
  end

  test "the re-enqueued gate actually releases a stuck clean post" do
    stale = pending_post(make_user, created_at: 30.minutes.ago)

    perform_enqueued_jobs do
      ModerationBacklogSweepJob.perform_now
    end

    assert stale.reload.moderation_approved?
  end
end
