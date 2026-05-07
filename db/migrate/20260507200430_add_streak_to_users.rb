class AddStreakToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :current_breath_streak, :integer, null: false, default: 0
    add_column :users, :longest_breath_streak, :integer, null: false, default: 0
    add_column :users, :streak_updated_on, :date
  end
end
