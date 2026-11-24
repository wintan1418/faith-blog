# frozen_string_literal: true

# Search v2: weighted, accent- and Unicode-style-insensitive vectors kept by
# triggers, replies indexed too, typo tolerance, a query log and recent
# searches.
#
# Safe with live traffic:
#   * no DDL transaction; every statement commits on its own
#   * new columns have no default (instant), triggers go in before the
#     backfill so rows written during it are already right
#   * the backfill runs in small id batches (each its own short transaction)
#   * every index is built CONCURRENTLY; the old one is dropped CONCURRENTLY
#     only after its replacement is ready
class RebuildSearch < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH = 2_000
  LIVE = "status = 1 AND moderation_status = 0"

  def up
    enable_extension "unaccent" unless extension_enabled?("unaccent")
    add_column :posts, :search_title, :text unless column_exists?(:posts, :search_title)
    add_column :comments, :searchable, :tsvector unless column_exists?(:comments, :searchable)

    SiteSearch::Schema.install!(connection)

    backfill("posts", <<~SQL)
      searchable = public.post_search_document(id, title, anonymous, user_id, room_id),
      search_title = public.search_key(title)
    SQL
    backfill("comments", "searchable = public.comment_search_document(id, content)")

    add_index :posts, :searchable, using: :gin, where: LIVE, name: "index_posts_search_live",
                                   algorithm: :concurrently, if_not_exists: true
    add_index :posts, :search_title, opclass: :gin_trgm_ops, using: :gin, where: LIVE,
                                     name: "index_posts_search_title_trgm", algorithm: :concurrently, if_not_exists: true
    # Exact-title matches always make the candidate list (btree, so long titles
    # are cut to their first 512 characters for the comparison).
    add_index :posts, "left(search_title, 512)", where: LIVE, name: "index_posts_search_title_exact",
                                                 algorithm: :concurrently, if_not_exists: true
    add_index :comments, :searchable, using: :gin, where: "deleted_at IS NULL AND moderation_status = 0",
                                      name: "index_comments_search_live", algorithm: :concurrently, if_not_exists: true
    # Newest visible replies first: lets a very common word stop early.
    add_index :comments, :created_at, order: { created_at: :desc }, where: "deleted_at IS NULL AND moderation_status = 0",
                                      name: "index_comments_live_created_at", algorithm: :concurrently, if_not_exists: true
    add_index :users, :id, where: "NOT active", name: "index_users_inactive", algorithm: :concurrently, if_not_exists: true
    # Legacy "held" breaths: a high-severity AI review nobody cleared.
    add_index :ai_moderation_reviews, :reviewable_id,
              where: "reviewable_type = 'Post' AND severity = 'high' AND status NOT IN (1, 4)",
              name: "index_ai_moderation_reviews_open_high_posts", algorithm: :concurrently, if_not_exists: true
    add_index :scripture_verses, "to_tsvector('english'::regconfig, text)", using: :gin, where: "translation = 'kjv'",
                                                                              name: "index_scripture_verses_kjv_search",
                                                                              algorithm: :concurrently, if_not_exists: true
    remove_index :posts, name: "index_posts_on_searchable", algorithm: :concurrently, if_exists: true

    create_search_tables
  end

  def down
    drop_table :search_queries, if_exists: true
    drop_table :search_terms, if_exists: true
    drop_table :recent_searches, if_exists: true
    remove_index :scripture_verses, name: "index_scripture_verses_kjv_search", algorithm: :concurrently, if_exists: true
    remove_index :ai_moderation_reviews, name: "index_ai_moderation_reviews_open_high_posts", algorithm: :concurrently, if_exists: true
    remove_index :comments, name: "index_comments_live_created_at", algorithm: :concurrently, if_exists: true
    remove_index :users, name: "index_users_inactive", algorithm: :concurrently, if_exists: true
    remove_index :comments, name: "index_comments_search_live", algorithm: :concurrently, if_exists: true
    remove_index :posts, name: "index_posts_search_title_exact", algorithm: :concurrently, if_exists: true
    remove_index :posts, name: "index_posts_search_title_trgm", algorithm: :concurrently, if_exists: true
    remove_index :posts, name: "index_posts_search_live", algorithm: :concurrently, if_exists: true
    SiteSearch::Schema.drop!(connection)
    remove_column :comments, :searchable, if_exists: true
    remove_column :posts, :search_title, if_exists: true
    # The old title + body vector (Post#refresh_search_vector filled it).
    execute <<~SQL
      UPDATE posts p SET searchable = to_tsvector('english', coalesce(p.title, '') || ' ' ||
        coalesce((SELECT regexp_replace(body, '<[^>]*>', ' ', 'g') FROM action_text_rich_texts r
                   WHERE r.record_type = 'Post' AND r.record_id = p.id AND r.name = 'content'), ''))
    SQL
    add_index :posts, :searchable, using: :gin, name: "index_posts_on_searchable", algorithm: :concurrently, if_not_exists: true
  end

  private

  def backfill(table, assignments)
    min, max = select_rows("SELECT min(id), max(id) FROM #{table}").first.map { |v| v&.to_i }
    return unless min

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (min..max).step(BATCH) do |from|
      execute("UPDATE #{table} SET #{assignments} WHERE id >= #{from} AND id < #{from + BATCH}")
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    say "backfilled #{table} (ids #{min}..#{max}) in #{elapsed.round(1)}s"
  end

  def create_search_tables
    # Normalized queries (no IP, no email-like or phone-like text) for the
    # admin's top / zero-result searches.
    create_table :search_queries, if_not_exists: true do |t|
      t.bigint :user_id
      t.string :query, limit: 120, null: false
      t.string :tab, limit: 20, null: false, default: "top"
      t.integer :results_count, null: false, default: 0
      t.boolean :filtered, null: false, default: false
      t.datetime :created_at, null: false
    end
    add_index :search_queries, :created_at, if_not_exists: true
    add_index :search_queries, %i[query created_at], if_not_exists: true

    # A member's recent searches (the header dropdown). They can clear them.
    create_table :recent_searches, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :query, limit: 120, null: false
      t.datetime :searched_at, null: false
    end
    add_index :recent_searches, %i[user_id query], unique: true, if_not_exists: true
    add_index :recent_searches, %i[user_id searched_at], if_not_exists: true

    # Words seen in public breaths, for "Did you mean …?" (SearchTermsRefreshJob).
    create_table :search_terms, id: false, if_not_exists: true do |t|
      t.string :term, limit: 40, null: false, primary_key: true
      t.integer :ndoc, null: false, default: 0
    end
    add_index :search_terms, :term, opclass: :gin_trgm_ops, using: :gin, name: "index_search_terms_trgm", if_not_exists: true
  end
end
