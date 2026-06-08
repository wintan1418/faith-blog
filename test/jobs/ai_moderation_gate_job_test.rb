# frozen_string_literal: true

require "test_helper"

class AiModerationGateJobTest < ActiveSupport::TestCase
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

  def pending_post(user, title: "A gentle breath", body: "Grace and peace to you.")
    Post.create!(
      user: user,
      room: Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x"),
      title: title,
      content: body,
      status: :published,
      moderation_status: :pending_review
    )
  end

  test "clean content is approved and released to the feed" do
    post = pending_post(make_user)

    assert_enqueued_with(job: BreathFanoutJob) do
      AiModerationGateJob.perform_now(post.id)
    end

    assert post.reload.moderation_approved?
    assert post.feed_visible?
  end

  test "job is a no-op once a post is no longer pending" do
    post = pending_post(make_user)
    post.update_column(:moderation_status, Post.moderation_statuses[:approved])

    assert_no_enqueued_jobs only: BreathFanoutJob do
      AiModerationGateJob.perform_now(post.id)
    end
  end

  test "missing post is handled gracefully" do
    assert_nothing_raised { AiModerationGateJob.perform_now(-1) }
  end
end
