# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :posts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.integer :status, default: 0, null: false
      t.boolean :featured, default: false, null: false
      t.integer :views_count, default: 0, null: false
      t.integer :likes_count, default: 0, null: false
      t.integer :comments_count, default: 0, null: false
      t.datetime :published_at
      t.datetime :scheduled_for
      t.boolean :allow_comments, default: true, null: false
      t.boolean :anonymous, default: false, null: false

      t.timestamps
    end

    add_index :posts, :slug, unique: true
    add_index :posts, :status
    add_index :posts, :featured
    add_index :posts, :published_at
    add_index :posts, :views_count
    add_index :posts, [:user_id, :status]
    add_index :posts, [:room_id, :status, :published_at]
  end
end

