class AddModerationStatusToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :moderation_status, :integer, null: false, default: 0
    add_column :posts, :moderation_blocked_reason, :string, limit: 280
    add_index  :posts, :moderation_status
  end
end
