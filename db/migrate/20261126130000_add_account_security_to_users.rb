# frozen_string_literal: true

# Email verification, two-step sign-in (authenticator app) and "sign out
# everywhere" for members.
#
# Members who joined with Google or Apple proved they own their address, so
# they start verified. Members who joined with a password start unverified:
# nothing is blocked for them, they see a gentle "Verify your email" banner.
class AddAccountSecurityToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime
    add_column :users, :otp_secret_ciphertext, :text
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_step, :bigint
    add_column :users, :otp_recovery_digests, :string, array: true, default: [], null: false
    # Sessions started before this time that have no device record are ended
    # ("Sign out everywhere else", "Secure my account").
    add_column :users, :sessions_reset_at, :datetime

    execute <<~SQL.squish
      UPDATE users SET email_verified_at = COALESCE(created_at, NOW())
      WHERE provider IS NOT NULL AND provider <> '' AND uid IS NOT NULL AND uid <> ''
    SQL
  end

  def down
    remove_column :users, :sessions_reset_at
    remove_column :users, :otp_recovery_digests
    remove_column :users, :otp_last_used_step
    remove_column :users, :otp_enabled_at
    remove_column :users, :otp_secret_ciphertext
    remove_column :users, :email_verified_at
  end
end
