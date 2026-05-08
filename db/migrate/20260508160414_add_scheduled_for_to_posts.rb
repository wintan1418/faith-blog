class AddScheduledForToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :scheduled_for, :datetime unless column_exists?(:posts, :scheduled_for)
    unless index_exists?(:posts, :scheduled_for)
      add_index :posts, :scheduled_for, where: "scheduled_for IS NOT NULL"
    end
  end
end
