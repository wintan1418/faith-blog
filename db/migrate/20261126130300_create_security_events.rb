# frozen_string_literal: true

# An audit trail of account security: sign-ins, codes sent and failed, 2FA
# changes, devices signed out, and admin actions (resend verification, reset
# 2FA). Admin → Users → Security shows a member's recent events.
class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      t.references :user, foreign_key: { on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false
      t.string :ip
      t.string :device_name
      t.string :location
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :security_events, [ :user_id, :created_at ]
    add_index :security_events, [ :kind, :ip, :created_at ]
  end
end
