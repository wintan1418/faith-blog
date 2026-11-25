# frozen_string_literal: true

# "Read your Bible, pray every day": one short prayer per Bible chapter
# (1,189 at most), written once by ChapterPrayerJob and stored, like
# scripture_insights. Pages never call the AI themselves.
class CreateChapterPrayers < ActiveRecord::Migration[8.1]
  def change
    create_table :chapter_prayers do |t|
      t.string :slug, limit: 80, null: false # the chapter page slug, e.g. "john-3"
      t.string :reference, limit: 80, null: false # "John 3"
      t.text :body, null: false
      t.jsonb :verses, null: false, default: [] # ["John 3:16", "John 3:17"]
      t.string :model, limit: 80
      t.datetime :generated_at, null: false
      t.timestamps
    end
    add_index :chapter_prayers, :slug, unique: true
  end
end
