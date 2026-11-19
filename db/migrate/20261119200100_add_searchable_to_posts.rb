# frozen_string_literal: true

# Post search used to build a tsvector from the title and every post's rich
# text body at query time. Store it instead (Post#refresh_search_vector keeps
# it current) and index it.
class AddSearchableToPosts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationPost < ActiveRecord::Base
    self.table_name = "posts"
  end

  def up
    add_column :posts, :searchable, :tsvector unless column_exists?(:posts, :searchable)
    add_index :posts, :searchable, using: :gin, algorithm: :concurrently, if_not_exists: true

    MigrationPost.select(:id, :title).find_in_batches(batch_size: 200) do |posts|
      bodies = ActionText::RichText.where(record_type: "Post", name: "content", record_id: posts.map(&:id))
                                   .index_by(&:record_id)
      posts.each do |post|
        body = bodies[post.id]&.body&.to_plain_text.to_s
        MigrationPost.where(id: post.id).update_all(
          [ "searchable = to_tsvector('english', coalesce(?, '') || ' ' || coalesce(?, ''))", post.title, body ]
        )
      end
    end
  end

  def down
    remove_index :posts, :searchable, algorithm: :concurrently, if_exists: true
    remove_column :posts, :searchable, if_exists: true
  end
end
