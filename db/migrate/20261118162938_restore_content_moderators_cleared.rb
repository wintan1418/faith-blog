# Comments and posts a moderator had already cleared (review dismissed) were
# left hidden: dismissing never restored them. Show them again.
class RestoreContentModeratorsCleared < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE comments SET moderation_status = 0, moderation_blocked_reason = NULL
      WHERE moderation_status IN (1, 2)
        AND id IN (SELECT reviewable_id FROM ai_moderation_reviews
                   WHERE reviewable_type = 'Comment' AND status = #{AiModerationReview.statuses.fetch("dismissed")})
    SQL
    execute <<~SQL
      UPDATE posts SET moderation_status = 0, moderation_blocked_reason = NULL
      WHERE moderation_status IN (1, 2)
        AND id IN (SELECT reviewable_id FROM ai_moderation_reviews
                   WHERE reviewable_type = 'Post' AND status = #{AiModerationReview.statuses.fetch("dismissed")})
    SQL
  end

  def down; end
end
