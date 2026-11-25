# frozen_string_literal: true

# Six-digit codes we email: verifying an address, confirming a sign-in from a
# new device, and confirming a new address before an email change. Only a
# keyed hash of each code (and of its one-tap link) is stored.
class CreateSecurityCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :security_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :purpose, null: false
      t.string :email, null: false
      t.string :code_digest, null: false
      t.string :link_digest
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :ip
      t.timestamps
    end
    add_index :security_codes, [ :user_id, :purpose, :created_at ]
    add_index :security_codes, :link_digest, unique: true
    add_index :security_codes, [ :ip, :created_at ]
  end
end
