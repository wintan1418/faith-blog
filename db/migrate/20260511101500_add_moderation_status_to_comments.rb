class AddModerationStatusToComments < ActiveRecord::Migration[8.0]
  def change
    add_column :comments, :moderation_status, :integer, null: false, default: 0
    add_column :comments, :moderation_blocked_reason, :string, limit: 280
    add_index  :comments, :moderation_status
  end
end
