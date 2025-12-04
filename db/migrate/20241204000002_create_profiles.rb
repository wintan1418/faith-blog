# frozen_string_literal: true

class CreateProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :bio
      t.string :location
      t.string :faith_background
      t.boolean :public_profile, default: true, null: false
      t.string :website
      t.jsonb :social_links, default: {}

      t.timestamps
    end
  end
end

