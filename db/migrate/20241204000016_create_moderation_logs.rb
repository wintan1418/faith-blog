# frozen_string_literal: true

class CreateModerationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :moderation_logs do |t|
      t.references :moderator, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.references :target, polymorphic: true, null: false
      t.text :notes
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :moderation_logs, :action
    add_index :moderation_logs, [:target_type, :target_id]
    add_index :moderation_logs, :created_at
  end
end

