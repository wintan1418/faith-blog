# frozen_string_literal: true

# "Say hello" from Breathers around you to someone you're not connected with
# sends a connection request; this marks those so they can be capped per day.
class AddViaAroundToConnectionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :connection_requests, :via_around, :boolean, null: false, default: false
    add_index :connection_requests, [ :sender_id, :created_at ], where: "via_around", name: "index_connection_requests_via_around"
  end
end
