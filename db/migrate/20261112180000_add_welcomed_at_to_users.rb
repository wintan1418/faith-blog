# frozen_string_literal: true

# When the founder's welcome note reached a member, so it's sent once; and a
# flag so that note's chat message doesn't also send a "new message" email
# (the member already gets the welcome email).
class AddWelcomedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :welcomed_at, :datetime
    add_column :messages, :quiet, :boolean, default: false, null: false
  end
end
