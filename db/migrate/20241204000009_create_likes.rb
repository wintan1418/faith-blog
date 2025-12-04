# frozen_string_literal: true

class CreateLikes < ActiveRecord::Migration[8.0]
  def change
    create_table :likes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :likeable, polymorphic: true, null: false
      t.integer :reaction_type, default: 0, null: false

      t.timestamps
    end

    add_index :likes, [:user_id, :likeable_type, :likeable_id], unique: true, name: 'index_likes_on_user_and_likeable'
    add_index :likes, :reaction_type
  end
end

