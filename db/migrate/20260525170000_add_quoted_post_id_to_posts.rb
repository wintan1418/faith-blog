# frozen_string_literal: true

class AddQuotedPostIdToPosts < ActiveRecord::Migration[8.0]
  def change
    add_reference :posts, :quoted_post,
                  foreign_key: { to_table: :posts, on_delete: :nullify },
                  null: true,
                  index: true
  end
end
