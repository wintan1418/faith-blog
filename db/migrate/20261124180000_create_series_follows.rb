# frozen_string_literal: true

# Readers who follow a series hear when a new part is added.
class CreateSeriesFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :series_follows do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :series, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.timestamps
    end
    add_index :series_follows, [ :user_id, :series_id ], unique: true
  end
end
