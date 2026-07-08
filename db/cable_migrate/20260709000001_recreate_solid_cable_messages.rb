# frozen_string_literal: true

# The production solid_cable_messages table was missing a proper primary-key
# unique index, so every broadcast (chat messages AND typing indicators) raised
# "No unique index found for id" and real-time delivery silently failed.
#
# solid_cable_messages holds only transient pub/sub rows (retained ~1 day), so
# dropping and recreating it with the correct structure is safe — no durable
# data lives here. This runs against the cable database via db:prepare on boot.
class RecreateSolidCableMessages < ActiveRecord::Migration[8.0]
  def up
    drop_table :solid_cable_messages, if_exists: true

    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 512.megabytes, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false

      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end

  def down
    # No-op: the table is transient and is (re)created by the initial
    # CreateSolidCableTables migration if needed.
  end
end
