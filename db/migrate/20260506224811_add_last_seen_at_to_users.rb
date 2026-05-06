class AddLastSeenAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :last_seen_at, :datetime
    add_index :users, :last_seen_at
  end
end
