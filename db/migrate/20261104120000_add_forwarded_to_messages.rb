# A forwarded message is a copy sent on to another chat; it shows "Forwarded".
class AddForwardedToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :forwarded, :boolean, null: false, default: false
  end
end
