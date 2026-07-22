# frozen_string_literal: true

class CreateUserBadges < ActiveRecord::Migration[8.0]
  def change
    create_table :user_badges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :slug, null: false
      t.datetime :awarded_at, null: false
      t.timestamps
    end

    add_index :user_badges, [ :user_id, :slug ], unique: true
  end
end
