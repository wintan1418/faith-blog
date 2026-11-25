# frozen_string_literal: true

# Pages in search: a weighted vector per page (name A, handle and tagline B,
# category, city and tradition C, about D) kept by a trigger, and page posts
# indexed under the page's name instead of the writer's.
class InstallPageSearch < ActiveRecord::Migration[8.1]
  def up
    SiteSearch::PageSchema.install!(connection)
    execute "UPDATE pages SET name = name"
    execute <<~SQL
      UPDATE posts SET searchable = public.post_search_document_v2(id, title, anonymous, user_id, room_id, page_id)
       WHERE page_id IS NOT NULL
    SQL
  end

  def down
    SiteSearch::PageSchema.drop!(connection)
  end
end
