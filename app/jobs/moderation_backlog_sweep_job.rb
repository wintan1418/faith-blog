# frozen_string_literal: true

# Safety net for the async moderation gate.
#
# A published post is created as :pending_review and AiModerationGateJob is
# expected to classify and release it within a second or two. If that job is
# ever lost — worker restart mid-deploy, a crash before Solid Queue persisted
# it, or a stretch where no worker was running at all — the post would
# otherwise stay hidden from the feed forever and never surface on the
# moderation board.
#
# This sweep finds any published post still stuck past the grace period and
# re-enqueues the gate. AiModerationGateJob is idempotent (it no-ops unless the
# post is still :pending_review) and fail-open (an unavailable AI provider
# releases the post), so re-running it can only move stuck posts forward.
class ModerationBacklogSweepJob < ApplicationJob
  queue_as :default

  GRACE = 10.minutes

  def perform
    Post.where(status: :published, moderation_status: :pending_review)
        .where(created_at: ..GRACE.ago)
        .find_each do |post|
      AiModerationGateJob.perform_later(post.id)
    end
  end
end
