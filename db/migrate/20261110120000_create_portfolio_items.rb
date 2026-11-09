# frozen_string_literal: true

# Portfolio: pieces of work on a member's profile (a design, an app, an
# article, a building, a recording, a campaign...), each with photos, a
# write-up, a link and an optional PDF.
class CreatePortfolioItems < ActiveRecord::Migration[8.1]
  def change
    create_table :portfolio_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, limit: 100
      t.string :summary, limit: 160
      t.text :description
      t.string :category, limit: 40
      t.string :contribution, limit: 80 # the part they played: "Lead designer"
      t.string :link_url, limit: 500
      t.string :skills, array: true, null: false, default: []
      t.date :completed_on
      t.integer :position, null: false, default: 0
      t.datetime :hidden_at # set when moderation takes it down
      t.timestamps
    end
    add_index :portfolio_items, [ :user_id, :position ]
  end
end
