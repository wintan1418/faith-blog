# This migration comes from action_push_native (originally 20250610075650)
class CreateActionPushNativeDevice < ActiveRecord::Migration[8.0]
  def change
    create_table :action_push_native_devices do |t|
      t.string :name
      t.string :platform, null: false
      t.string :token, null: false
      t.belongs_to :owner, polymorphic: true

      t.timestamps

      # One row per phone install; re-registering moves it to whoever signed in.
      t.index :token, unique: true
    end
  end
end
