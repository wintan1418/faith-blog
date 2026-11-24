# frozen_string_literal: true

# Who brought a member in: the personal invite link (/join/username) or an
# accepted email invitation. Nullified when the inviter's account goes.
class AddInvitedByToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
