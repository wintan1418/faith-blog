class AddAppleRefreshTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    # From Sign in with Apple; revoked with Apple when the account is deleted.
    add_column :users, :apple_refresh_token, :string
  end
end
