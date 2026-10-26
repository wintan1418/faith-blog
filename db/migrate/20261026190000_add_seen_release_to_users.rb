# frozen_string_literal: true

# The "What's new" pop-up shows each release once per person (remembered on the account).
class AddSeenReleaseToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :seen_release_id, :bigint
  end
end
