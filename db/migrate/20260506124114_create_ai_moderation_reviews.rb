class CreateAiModerationReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_moderation_reviews do |t|
      t.references :reviewable, polymorphic: true, null: false, index: true
      t.references :user, foreign_key: true, index: true

      t.integer :status, null: false, default: 0
      t.string  :severity, null: false, default: "none"
      t.string  :recommended_action, null: false, default: "allow"
      t.string  :categories, array: true, default: [], null: false
      t.float   :score, null: false, default: 0.0
      t.string  :summary
      t.string  :model
      t.jsonb   :raw_response, default: {}, null: false

      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :ai_moderation_reviews, :status
    add_index :ai_moderation_reviews, :severity
    add_index :ai_moderation_reviews, :reviewed_at
    add_index :ai_moderation_reviews, :categories, using: :gin
  end
end
