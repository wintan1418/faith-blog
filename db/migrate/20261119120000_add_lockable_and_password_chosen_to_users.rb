# frozen_string_literal: true

# Devise :lockable (lock after repeated failed sign-ins, unlock by email or
# after a cool-down) and password_chosen_at — when the member last picked
# their own password. Accounts created through Google / Apple get a random
# password nobody knows, so they have no "current password" to confirm.
class AddLockableAndPasswordChosenToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_column :users, :password_chosen_at, :datetime
    add_index :users, :unlock_token, unique: true

    # Accounts that signed up with email + password chose their password.
    # Google / Apple accounts stay NULL: they may never have known it.
    execute <<~SQL.squish
      UPDATE users SET password_chosen_at = created_at WHERE provider IS NULL OR provider = ''
    SQL
  end

  def down
    remove_index :users, :unlock_token
    remove_column :users, :password_chosen_at
    remove_column :users, :locked_at
    remove_column :users, :unlock_token
    remove_column :users, :failed_attempts
  end
end
