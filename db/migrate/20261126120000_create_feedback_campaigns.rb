# frozen_string_literal: true

# Admin feedback surveys ("How is Brethreign working for you?") and the
# members' answers. One feedback_responses row per member per campaign holds
# both the answer and the pop-up state (snoozed / declined).
class CreateFeedbackCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :feedback_campaigns do |t|
      t.string :title, null: false, limit: 160
      t.integer :rating_kind, null: false, default: 0
      t.string :follow_up_prompt, limit: 200
      t.string :choice_question, limit: 200
      t.string :choice_options, array: true, null: false, default: []
      t.integer :audience, null: false, default: 0
      t.boolean :also_push, null: false, default: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :launched_at
      t.datetime :delivered_at
      t.datetime :closed_at
      t.integer :targeted_count, null: false, default: 0
      t.integer :responses_count, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :feedback_campaigns, [ :launched_at, :starts_at ]

    create_table :feedback_responses do |t|
      t.references :feedback_campaign, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :rating
      t.text :comment
      t.string :choice, limit: 120
      t.string :platform, limit: 20
      t.datetime :submitted_at
      t.datetime :declined_at
      t.datetime :snoozed_until
      t.integer :snooze_count, null: false, default: 0
      t.timestamps
    end
    add_index :feedback_responses, [ :user_id, :feedback_campaign_id ], unique: true
    add_index :feedback_responses, [ :feedback_campaign_id, :submitted_at ], name: "index_feedback_responses_on_campaign_and_submitted"
  end
end
