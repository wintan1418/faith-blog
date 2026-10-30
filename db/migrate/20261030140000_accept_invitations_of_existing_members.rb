# frozen_string_literal: true

# Invitations to people who already joined (by Google, in the app, or
# without the invite link) were left "Pending". Mark them accepted.
class AcceptInvitationsOfExistingMembers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE invitations
      SET invited_user_id = users.id,
          accepted_at = GREATEST(users.created_at, invitations.created_at),
          updated_at = NOW()
      FROM users
      WHERE invitations.accepted_at IS NULL
        AND LOWER(users.email) = invitations.email
    SQL
  end

  def down
    # Nothing to undo: these people did join.
  end
end
