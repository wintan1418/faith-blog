class CreateConnectionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :connection_requests do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :receiver, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false
      t.text :message

      t.timestamps
    end

    add_index :connection_requests, [:sender_id, :receiver_id], unique: true
    add_index :connection_requests, :status
  end
end

