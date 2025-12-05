# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.references :parent_comment, foreign_key: { to_table: :comments }
      t.text :content, null: false
      t.datetime :edited_at
      t.datetime :deleted_at
      t.boolean :flagged, default: false, null: false
      t.integer :likes_count, default: 0, null: false
      t.integer :replies_count, default: 0, null: false

      t.timestamps
    end

    add_index :comments, [:post_id, :created_at]
    # parent_comment_id index is automatically created by t.references above
    add_index :comments, :flagged
    add_index :comments, :deleted_at
  end
end

