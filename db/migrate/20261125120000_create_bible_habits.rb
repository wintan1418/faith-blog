# frozen_string_literal: true

# "Have you read your Bible today?": one row per member with their reading
# plan, where they are in it, their reading streak (in their own time zone)
# and their daily reminder. After reading, a short prayer from the chapter
# ("Read your Bible, pray every day").
class CreateBibleHabits < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_habits do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :plan_slug, null: false, default: "chapter-a-day"
      # Portions finished in each plan, so switching plans and back resumes.
      t.jsonb :plan_positions, null: false, default: {}
      t.string :time_zone, null: false, default: "Africa/Lagos"

      t.integer :current_streak, null: false, default: 0
      t.integer :longest_streak, null: false, default: 0
      t.integer :days_read, null: false, default: 0
      t.date :last_read_on
      t.date :last_prayed_on
      t.boolean :show_streak, null: false, default: true

      # The feed card: folded down or put away, for one local day.
      t.date :card_collapsed_on
      t.date :card_hidden_on

      # Minutes after local midnight (420 = 7:00). next_reminder_at is the UTC
      # moment that is due next, so the job only reads rows that are due.
      t.boolean :reminder_enabled, null: false, default: true
      t.integer :reminder_minute, null: false, default: 420
      t.datetime :next_reminder_at
      t.date :last_reminded_on

      t.timestamps
    end
    add_index :bible_habits, :next_reminder_at, where: "reminder_enabled"
    add_index :bible_habits, :last_read_on
  end
end
