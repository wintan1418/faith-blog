# frozen_string_literal: true

class CreateRoomMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :room_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.boolean :notifications_enabled, default: true, null: false

      t.timestamps
    end

    add_index :room_memberships, [:user_id, :room_id], unique: true
    add_index :room_memberships, :role
  end
end

