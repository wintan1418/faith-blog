class AddAccentColorToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :accent_color, :string, limit: 16, null: false, default: "mint"
    add_index  :users, :accent_color
  end
end
