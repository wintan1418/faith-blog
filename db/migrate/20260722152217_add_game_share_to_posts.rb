class AddGameShareToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :game_share, :jsonb
  end
end
