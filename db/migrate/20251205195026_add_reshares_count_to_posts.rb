class AddResharesCountToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :reshares_count, :integer, default: 0, null: false
  end
end
