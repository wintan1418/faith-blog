# frozen_string_literal: true

# Track which waitlist emails each person has had, so a launch email
# never goes out twice and a confirmation isn't repeated.
class AddNotifiedToAppWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :app_waitlist_entries, :confirmed_at, :datetime
    add_column :app_waitlist_entries, :ios_notified_at, :datetime
    add_column :app_waitlist_entries, :android_notified_at, :datetime
  end
end
