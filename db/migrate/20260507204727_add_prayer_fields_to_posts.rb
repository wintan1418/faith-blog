class AddPrayerFieldsToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :prayer_status, :integer, null: false, default: 0
    add_column :posts, :intercessions_count, :integer, null: false, default: 0
    add_column :posts, :prayer_answered_at, :datetime

    add_index :posts, :prayer_status
  end
end
