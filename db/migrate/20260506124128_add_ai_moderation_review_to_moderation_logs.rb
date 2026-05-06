class AddAiModerationReviewToModerationLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :moderation_logs, :ai_moderation_review, null: true, foreign_key: true
  end
end
