# frozen_string_literal: true

# Safety net for the async moderation gate.
#
# Publish-first flow: a breath goes live at create and AiModerationGateJob
# classifies it in the background. If that job is ever lost — worker restart
# mid-deploy, a crash before Solid Queue persisted it, or a stretch where no
# worker was running at all — the post would stay unclassified (or, for
# legacy posts, stuck hidden in :pending_review) and never surface on the
# moderation board.
#
# This sweep re-enqueues the gate for both cases. AiModerationGateJob is
# idempotent (it no-ops once a review is settled) and fail-open (an
# unavailable AI provider releases rather than holds), so re-running it can
# only move posts forward.
class ModerationBacklogSweepJob < ApplicationJob
  queue_as :default

  GRACE  = 10.minutes
  WINDOW = 7.days # don't trawl all of history for unclassified legacy posts

  def perform
    ids = Post.where(status: :published, moderation_status: :pending_review)
              .where(created_at: ..GRACE.ago)
              .pluck(:id)

    ids |= Post.where(status: :published)
               .where(created_at: WINDOW.ago..GRACE.ago)
               .where.missing(:ai_moderation_review)
               .pluck(:id)

    ids.each { |id| AiModerationGateJob.perform_later(id) }
  end
end
