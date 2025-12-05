class CreatePostLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :post_links do |t|
      t.references :source_post, null: false, foreign_key: { to_table: :posts }
      t.references :target_post, null: false, foreign_key: { to_table: :posts }
      t.string :link_type, default: 'related' # related, reference, continuation, response

      t.timestamps
    end

    add_index :post_links, [:source_post_id, :target_post_id], unique: true
  end
end

