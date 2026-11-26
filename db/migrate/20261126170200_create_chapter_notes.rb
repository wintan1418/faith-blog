# frozen_string_literal: true

# A member's own notes on one Bible chapter ("My notes" on the chapter page).
# Private: only the writer ever sees them, unless they choose to include them
# when sharing what they read.
class CreateChapterNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :chapter_notes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :slug, limit: 80, null: false # the chapter page slug, e.g. "john-1"
      t.text :body, null: false
      t.timestamps
    end
    add_index :chapter_notes, %i[user_id slug], unique: true
  end
end
