# frozen_string_literal: true

# Chapter prayers become a prayer burden: a one-line summary of what the
# chapter calls us to pray about, 3-5 prayer points each tied to a verse, a
# closing prayer (body), and the themes and key verses they were drawn from.
# Rows written before this (version 1, a single short prayer) are rewritten
# lazily on the next view and by `bin/rails "bible_today:prayers[N]"`.
class AddPrayerBurdenToChapterPrayers < ActiveRecord::Migration[8.1]
  def change
    change_table :chapter_prayers, bulk: true do |t|
      t.integer :version, null: false, default: 1
      t.text :burden
      t.jsonb :points, null: false, default: [] # [{ "text", "reference", "kind" }]
      t.jsonb :key_verses, null: false, default: [] # ["John 1:14"]
      t.jsonb :themes, null: false, default: [] # ["The Word made flesh"]
    end
    add_index :chapter_prayers, :version
  end
end
