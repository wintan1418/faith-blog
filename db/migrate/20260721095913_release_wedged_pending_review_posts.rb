# frozen_string_literal: true

# One-time cleanup for the born-held era: published posts wedged in
# :pending_review that were never actually decided (no pending/flagged AI
# review row) go live. Posts an AI review genuinely held stay held for the
# moderators. Plain SQL on purpose — no callbacks, no fanout spam for old
# breaths. New posts are born :approved and classified in the background.
class ReleaseWedgedPendingReviewPosts < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE posts
      SET moderation_status = 0 /* approved */
      WHERE status = 1 /* published */
        AND moderation_status = 1 /* pending_review */
        AND id NOT IN (
          SELECT reviewable_id FROM ai_moderation_reviews
          WHERE reviewable_type = 'Post' AND status IN (0 /* pending */, 2 /* flagged */)
        )
    SQL
  end

  def down
    # No-op: we can't know which posts were wedged before the release.
  end
end
