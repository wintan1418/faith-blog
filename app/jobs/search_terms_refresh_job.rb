# frozen_string_literal: true

# Rebuilds the word list behind "Did you mean …?" from the newest public
# breaths (what a signed-out visitor could read: no private, prayer or
# struggles rooms, no anonymous breaths), and prunes the search log.
# Bounded work: SAMPLE breaths at most, however big the site gets.
class SearchTermsRefreshJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(*) { "search-terms-refresh" }, duration: 30.minutes

  SAMPLE = 50_000
  MIN_DOCS = 2
  LOG_RETENTION = 180.days

  def perform(*)
    public_posts = SiteSearch::Visibility.new(nil).posts_sql("p")
    inner = <<~SQL
      SELECT to_tsvector('simple', public.search_fold(coalesce(p.title, '') || ' ' || public.search_html_text(r.body)))
      FROM posts p
      LEFT JOIN action_text_rich_texts r ON r.record_type = 'Post' AND r.record_id = p.id AND r.name = 'content'
      WHERE #{public_posts}
      ORDER BY p.published_at DESC
      LIMIT #{SAMPLE}
    SQL

    ApplicationRecord.transaction do
      conn = ApplicationRecord.connection
      conn.execute("DELETE FROM search_terms")
      conn.execute(<<~SQL)
        INSERT INTO search_terms (term, ndoc)
        SELECT word, ndoc FROM ts_stat(#{conn.quote(inner)})
        WHERE ndoc >= #{MIN_DOCS} AND length(word) BETWEEN 3 AND 40 AND word ~ '^[a-z]+$'
      SQL
    end
    # Fresh statistics, so lookups use the trigram index instead of a scan.
    ApplicationRecord.connection.execute("ANALYZE search_terms")

    SearchQuery.where(created_at: ...LOG_RETENTION.ago).in_batches(of: 5_000).delete_all
  end
end
