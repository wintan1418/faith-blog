class CreateBroadcasts < ActiveRecord::Migration[8.0]
  def change
    create_table :broadcasts do |t|
      t.string     :subject, null: false, limit: 200
      t.string     :preheader, limit: 200
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.integer    :status, null: false, default: 0
      t.datetime   :sent_at
      t.integer    :recipients_count, null: false, default: 0

      t.timestamps
    end
    add_index :broadcasts, :status
  end
end
