class CreateUserRiskProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :user_risk_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.integer :risk_level, null: false, default: 0
      t.float   :risk_score, null: false, default: 0.0

      t.integer :flagged_reviews_count,        null: false, default: 0
      t.integer :confirmed_violations_count,   null: false, default: 0
      t.integer :dismissed_flags_count,        null: false, default: 0

      t.datetime :last_flagged_at
      t.datetime :last_action_at

      t.timestamps
    end

    add_index :user_risk_profiles, :risk_level
    add_index :user_risk_profiles, :last_flagged_at
  end
end
