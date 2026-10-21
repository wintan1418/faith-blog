# Keep moderation logs and admin broadcasts when their author deletes their
# account (the author becomes nil) instead of blocking the deletion.
class AllowDeletedAuthorsOnAuditRecords < ActiveRecord::Migration[8.1]
  def change
    change_column_null :moderation_logs, :moderator_id, true
    change_column_null :broadcasts, :sender_id, true
  end
end
