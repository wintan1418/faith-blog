# frozen_string_literal: true

# Telling search engines which public pages changed (Admin → Search & indexing).
#
# Models opt in with SearchIndexable: they say whether a record is a public,
# indexable page and which URLs it has. Changed URLs wait in
# indexing_pending_urls for a few minutes and then go to IndexNow in one batch
# (IndexNowFlushJob). Private, anonymous and prayer breaths, private rooms and
# noindex pages (/join/*, /in/*) are never sent.
module SearchIndexing
  HOST = "brethreign.com"
  BASE_URL = "https://#{HOST}"
  DEBOUNCE = 5.minutes
  STALE_PENDING = 15.minutes

  # Paths that are noindex or not public, whatever page type produced them.
  NOINDEX_PATH = %r{\A/(join|in|admin|users|settings|messages|conversations|notifications|office|api|rails)(/|\z)}

  # Route helpers that build https://brethreign.com URLs from anywhere.
  class Urls
    include Rails.application.routes.url_helpers

    def default_url_options = { host: SearchIndexing::HOST, protocol: "https" }
  end

  module_function

  def url_helpers
    @url_helpers ||= Urls.new
  end

  # An https URL on brethreign.com whose path isn't a noindex/private area.
  def public_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host == HOST && uri.userinfo.nil? && uri.query.nil? &&
      !uri.path.to_s.match?(NOINDEX_PATH)
  rescue URI::InvalidURIError
    false
  end

  # Stricter check for a URL an admin types in: breath, room and resource URLs
  # must point at a record that is itself indexable right now.
  def submittable_url?(url)
    return false unless public_url?(url)

    path = URI.parse(url).path
    case path
    when %r{\A/posts/([^/]+)\z} then indexable_record?(Post, ::Regexp.last_match(1))
    when %r{\A/rooms/([^/]+)\z} then indexable_record?(Room, ::Regexp.last_match(1))
    when %r{\A/resources/([^/]+)\z} then indexable_record?(Resource, ::Regexp.last_match(1))
    else true
    end
  end

  def indexable_record?(model, slug)
    record = model.friendly.find(slug)
    record.search_indexable?
  rescue ActiveRecord::RecordNotFound
    false
  end

  # Adds URLs to the next IndexNow batch. Starts the batch timer when the
  # waiting list was empty (or looks stuck). Returns the URLs it accepted.
  def queue(urls, source: nil)
    return [] unless IndexNow.enabled?

    urls = Array(urls).map(&:to_s).uniq.select { |url| public_url?(url) }
    return [] if urls.empty?

    start_timer = !IndexingPendingUrl.exists? ||
                  IndexingPendingUrl.where(created_at: ...STALE_PENDING.ago).exists?
    now = Time.current
    IndexingPendingUrl.upsert_all(
      urls.map { |url| { url: url, source: source&.to_s&.first(40), created_at: now, updated_at: now } },
      unique_by: :url, on_duplicate: :skip
    )
    IndexNowFlushJob.set(wait: DEBOUNCE).perform_later if start_timer
    urls
  end

  # Every public URL that changed since `since`: opted-in records, blog
  # articles dated in the window, and the home page when anything changed.
  def recently_changed_urls(since:)
    urls = SearchIndexable.models.flat_map do |model|
      model.search_index_candidates(since).filter_map do |record|
        record.search_index_urls if record.search_indexable?
      end.flatten
    end
    urls += BlogArticle.all.select { |a| a.date && a.date >= since.to_date }.map { |a| url_helpers.blog_article_url(a.slug) }
    urls.unshift(url_helpers.root_url) if urls.any?
    urls.uniq.select { |url| public_url?(url) }
  end
end
