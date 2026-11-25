# frozen_string_literal: true

# A post written "as" a page, and a profile role that links to a page
# (shown on the page's People tab only when the member says so).
class AddPageToPostsAndExperiences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :posts, :page_id, :bigint, if_not_exists: true
    add_index :posts, %i[page_id published_at], where: "page_id IS NOT NULL", algorithm: :concurrently,
                                                if_not_exists: true
    add_foreign_key :posts, :pages, on_delete: :nullify, if_not_exists: true

    add_column :experiences, :page_id, :bigint, if_not_exists: true
    add_column :experiences, :listed_on_page, :boolean, default: false, null: false, if_not_exists: true
    add_index :experiences, :page_id, where: "page_id IS NOT NULL", algorithm: :concurrently, if_not_exists: true
    add_foreign_key :experiences, :pages, on_delete: :nullify, if_not_exists: true
  end
end
