# frozen_string_literal: true

# When the member last looked at the top of the feed. Posts newer than this
# are "new" for them (the New posts pill and the small dot on cards).
class AddFeedSeenAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :feed_seen_at, :datetime
  end
end
