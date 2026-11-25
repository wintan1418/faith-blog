# frozen_string_literal: true

# The people a member chose to share their contact details with ("People I
# choose", or "Share my contact" from a profile or a chat).
class CreateContactShares < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_shares do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      t.references :viewer, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
    end
    add_index :contact_shares, [ :owner_id, :viewer_id ], unique: true
  end
end
