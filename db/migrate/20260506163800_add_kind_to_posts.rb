class AddKindToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :kind, :integer, null: false, default: 0
    add_index :posts, :kind
  end
end
