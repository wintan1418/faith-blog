# frozen_string_literal: true

class CreateRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :rooms do |t|
      t.string :name, null: false
      t.text :description
      t.string :slug, null: false
      t.integer :room_type, default: 0, null: false
      t.boolean :is_public, default: true, null: false
      t.text :rules
      t.string :icon
      t.string :color
      t.integer :posts_count, default: 0, null: false
      t.integer :members_count, default: 0, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :rooms, :slug, unique: true
    add_index :rooms, :room_type
    add_index :rooms, :is_public
    add_index :rooms, :position
  end
end

