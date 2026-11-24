# frozen_string_literal: true

# Google Search Console, read-only reports plus sitemap submit. Off until
# GOOGLE_SEARCH_CONSOLE_CREDENTIALS holds a service account key (the JSON
# itself, or a path to the file). The property defaults to the domain property
# sc-domain:brethreign.com (GOOGLE_SEARCH_CONSOLE_SITE overrides it).
#
# Endpoints used, nothing else:
#   webmasters v3  sitemaps.list, sitemaps.submit, searchanalytics.query
#   searchconsole v1  urlInspection.index.inspect
#
# Google has no public API for "Request indexing" on ordinary pages, so the
# admin page links to Search Console for that.
module SearchConsole
  class Error < StandardError; end

  DEFAULT_SITE = "sc-domain:brethreign.com"
  SITEMAP_URL = "#{SearchIndexing::BASE_URL}/sitemap.xml".freeze
  PERIODS = { "28d" => 28, "3m" => 90 }.freeze
  TOP_ROWS = 25

  module_function

  def configured?
    creds = credentials
    creds.present? && creds["client_email"].present? && creds["private_key"].present?
  end

  def site
    ENV["GOOGLE_SEARCH_CONSOLE_SITE"].presence || DEFAULT_SITE
  end

  def service_account_email
    credentials&.dig("client_email")
  end

  # The service account key as a Hash, or nil. Never logged.
  def credentials
    raw = ENV["GOOGLE_SEARCH_CONSOLE_CREDENTIALS"].to_s.strip
    return nil if raw.empty?

    raw = File.read(raw) unless raw.start_with?("{")
    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError, SystemCallError
    nil
  end

  def client
    raise Error, "Google Search Console isn't connected" unless configured?

    Client.new(credentials: credentials, site: site)
  end

  # Link to Search Console's URL inspection, where "Request indexing" lives.
  def inspect_link(url)
    "https://search.google.com/search-console/inspect?resource_id=#{CGI.escape(site)}&id=#{CGI.escape(url.to_s)}"
  end

  def property_link
    "https://search.google.com/search-console?resource_id=#{CGI.escape(site)}"
  end
end
