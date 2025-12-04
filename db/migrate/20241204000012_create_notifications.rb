# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true, null: false
      t.integer :notification_type, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [:user_id, :read_at]
    add_index :notifications, [:user_id, :created_at]
    add_index :notifications, :notification_type
  end
end

