# frozen_string_literal: true

# "Get the app" on the welcome page: people who want an email when the iPhone /
# Android app is out. One row per email (case-insensitive).
class CreateAppWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :app_waitlist_entries do |t|
      t.string :email, null: false
      t.string :platform, null: false, default: "both"
      t.string :source
      t.string :ip_hash
      t.timestamps
    end
    add_index :app_waitlist_entries, "lower(email)", unique: true, name: "index_app_waitlist_entries_on_lower_email"
    add_index :app_waitlist_entries, :created_at
  end
end
