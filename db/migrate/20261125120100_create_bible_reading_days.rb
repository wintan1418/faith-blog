# frozen_string_literal: true

# One row per member per local day they read Scripture: the streak, the
# "N brethren read today" count and the once-a-day seeds all hang off it.
class CreateBibleReadingDays < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_reading_days do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :read_on, null: false
      t.string :plan_slug
      t.string :first_chapter # slug of the first chapter read that day, e.g. "john-3"
      t.string :source, null: false # card, chapter or dwell
      t.integer :portions_completed, null: false, default: 0
      t.datetime :prayed_at # "Amen" on the day's prayer
      t.timestamps
    end
    add_index :bible_reading_days, [ :user_id, :read_on ], unique: true
    add_index :bible_reading_days, :read_on
  end
end
