# frozen_string_literal: true

# The phones and browsers a member signs in on (Settings → Security). A device
# is recognised by a long-lived signed cookie (or the app's install id); only
# a keyed hash of it is stored. Each signed-in session on the device carries a
# random token whose hash lives here, so a device can be signed out remotely.
class CreateUserDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :user_devices do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :device_digest, null: false
      t.string :session_digest
      t.string :name, null: false
      t.string :platform, null: false, default: "web"
      t.string :user_agent
      t.string :ip
      t.string :location
      t.datetime :verified_at
      t.datetime :trusted_until
      t.datetime :signed_in_at
      t.datetime :last_active_at
      t.datetime :signed_out_at
      t.string :push_token
      t.timestamps
    end
    add_index :user_devices, [ :user_id, :device_digest ], unique: true
    add_index :user_devices, :session_digest, unique: true
  end
end
