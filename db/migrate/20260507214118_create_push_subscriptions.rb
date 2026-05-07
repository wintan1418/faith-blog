class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint, null: false, limit: 1024
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.datetime :last_pushed_at

      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
