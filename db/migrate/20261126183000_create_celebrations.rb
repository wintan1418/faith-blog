# frozen_string_literal: true

# Brethreign Celebrates: special occasions (Christmas, Easter, national days…)
# shown to members as a feed banner, a strip on other pages and a share card.
class CreateCelebrations < ActiveRecord::Migration[8.1]
  def change
    create_table :celebrations do |t|
      t.string :name, null: false
      # Set on built-in calendar presets ("thanksgiving-us-2026"), so the
      # seed task never creates the same occasion twice.
      t.string :preset_key
      t.string :greeting_title, null: false
      t.text :message
      t.string :scripture_reference
      t.text :scripture_text
      t.string :hashtag
      t.string :accent_color, null: false, default: "#0e5c43"
      t.string :emblem
      t.string :effect, null: false, default: "none"
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :time_zone, null: false, default: "Africa/Lagos"
      t.integer :audience, null: false, default: 0
      t.string :country_codes, array: true, null: false, default: []
      t.references :post, foreign_key: { on_delete: :nullify }
      t.boolean :share_card, null: false, default: true
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :celebrations, :preset_key, unique: true
    add_index :celebrations, %i[status ends_at]
  end
end
