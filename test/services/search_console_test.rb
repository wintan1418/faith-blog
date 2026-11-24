# frozen_string_literal: true

require "test_helper"
require_relative "../support/search_indexing_stubs"

# Google Search Console: configuration, the signed JWT, the exact requests,
# token reuse, and the reports stored in the database.
class SearchConsoleTest < ActiveSupport::TestCase
  include SearchIndexingStubs

  def client = SearchConsole::Client.new(credentials: fake_google_credentials, site: "sc-domain:brethreign.com")

  def decode(segment) = JSON.parse(Base64.urlsafe_decode64(segment + "=" * (-segment.size % 4)))

  setup { SearchConsole::Client.reset_tokens! }

  test "off until credentials are set; reads JSON or a file path" do
    with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => nil) { refute SearchConsole.configured? }
    with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => "not json") { refute SearchConsole.configured? }
    with_google do
      assert SearchConsole.configured?
      assert_equal "indexer@brethreign-test.iam.gserviceaccount.com", SearchConsole.service_account_email
      assert_equal "sc-domain:brethreign.com", SearchConsole.site
    end
    Tempfile.create([ "sa", ".json" ]) do |file|
      file.write(fake_google_credentials.to_json)
      file.flush
      with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => file.path) { assert SearchConsole.configured? }
    end
  end

  test "the JWT assertion is RS256-signed with the service account key" do
    now = 1_700_000_000
    header, claims, signature = client.jwt_assertion(now).split(".")
    assert_equal({ "alg" => "RS256", "typ" => "JWT" }, decode(header))
    assert_equal({ "iss" => "indexer@brethreign-test.iam.gserviceaccount.com", "scope" => "https://www.googleapis.com/auth/webmasters",
                   "aud" => "https://oauth2.googleapis.com/token", "iat" => now, "exp" => now + 3600 }, decode(claims))
    raw_signature = Base64.urlsafe_decode64(signature + "=" * (-signature.size % 4))
    assert FAKE_KEY.public_key.verify(OpenSSL::Digest.new("SHA256"), raw_signature, "#{header}.#{claims}")
  end

  test "exchanges the JWT for a token once and reuses it" do
    stub_google(->(*) { [ 200, { sitemap: [] } ] }) do |calls|
      2.times { client.sitemaps }
      token_calls = calls.select { |c| c[:url] == "https://oauth2.googleapis.com/token" }
      assert_equal 1, token_calls.size
      form = URI.decode_www_form(token_calls.first[:body]).to_h
      assert_equal "urn:ietf:params:oauth:grant-type:jwt-bearer", form["grant_type"]
      assert_equal 3, form["assertion"].split(".").size
      assert_equal "application/x-www-form-urlencoded", token_calls.first[:headers]["Content-Type"]
      assert_equal "Bearer ya29.test-token", calls.last[:headers]["Authorization"]
    end
  end

  test "request shapes for sitemaps, search analytics and URL inspection" do
    stub_google(->(*) { [ 200, { rows: [], sitemap: [], inspectionResult: { "indexStatusResult" => { "verdict" => "PASS" } } } ] }) do |calls|
      c = client
      c.sitemaps
      c.submit_sitemap
      c.search_analytics(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 28), dimensions: [ "query" ], row_limit: 25)
      result = c.inspect_url("https://brethreign.com/posts/x")
      assert_equal "PASS", result.dig("indexStatusResult", "verdict")

      api = calls.reject { |x| x[:url].include?("oauth2") }
      base = "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Abrethreign.com"
      assert_equal [ :get, "#{base}/sitemaps" ], api[0].values_at(:method, :url)
      assert_equal [ :put, "#{base}/sitemaps/https%3A%2F%2Fbrethreign.com%2Fsitemap.xml" ], api[1].values_at(:method, :url)
      assert_equal [ :post, "#{base}/searchAnalytics/query" ], api[2].values_at(:method, :url)
      assert_equal({ "startDate" => "2026-10-01", "endDate" => "2026-10-28", "dimensions" => [ "query" ], "rowLimit" => 25, "dataState" => "final" },
                   JSON.parse(api[2][:body]))
      assert_equal [ :post, "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect" ], api[3].values_at(:method, :url)
      assert_equal({ "inspectionUrl" => "https://brethreign.com/posts/x", "siteUrl" => "sc-domain:brethreign.com", "languageCode" => "en-US" },
                   JSON.parse(api[3][:body]))
    end
  end

  test "Google errors become SearchConsole::Error without the key" do
    stub_google(->(*) { [ 403, { error: { message: "User does not have sufficient permission" } } ] }) do
      error = assert_raises(SearchConsole::Error) { client.sitemaps }
      assert_match "sufficient permission", error.message
      refute_match "PRIVATE KEY", error.message
    end
  end

  test "refresh stores every report in the database, keeping old data on failure" do
    responder = lambda do |_method, url, body|
      next [ 200, { sitemap: [ { path: "https://brethreign.com/sitemap.xml", isPending: false, errors: "0", warnings: "0" } ] } ] if url.end_with?("/sitemaps")

      dims = JSON.parse(body)["dimensions"]
      rows = case dims
      when [] then [ { clicks: 120, impressions: 4000, ctr: 0.03, position: 14.2 } ]
      when [ "query" ] then [ { keys: [ "brethreign" ], clicks: 50, impressions: 90, ctr: 0.55, position: 1.1 } ]
      else [ { keys: [ "https://brethreign.com/" ], clicks: 40, impressions: 300, ctr: 0.13, position: 3.0 } ]
      end
      [ 200, { rows: rows } ]
    end
    stub_google(responder) do |calls|
      errors = SearchConsole::Refresh.call(client, today: Date.new(2026, 11, 24))
      assert_empty errors
      first_totals = calls.find { |c| c[:url].end_with?("/query") }
      assert_equal({ "startDate" => "2026-10-27", "endDate" => "2026-11-23" }, JSON.parse(first_totals[:body]).slice("startDate", "endDate"))
    end
    assert_equal 120, SearchConsoleReport.data_for("totals_28d")["clicks"]
    assert_equal "brethreign", SearchConsoleReport.data_for("queries_3m")["rows"].first["key"]
    assert_equal 1, SearchConsoleReport.data_for("pages_seen_3m")["count"]
    assert_equal "https://brethreign.com/sitemap.xml", SearchConsoleReport.data_for("sitemaps")["sitemaps"].first["path"]
    assert SearchConsoleReport.data_for("status")["ok"]

    stub_google(->(*) { [ 500, { error: { message: "Backend Error" } } ] }) do
      SearchConsole::Refresh.call(client)
    end
    assert_equal 120, SearchConsoleReport.data_for("totals_28d")["clicks"], "kept the last good numbers"
    assert_match "Backend Error", SearchConsoleReport.for("totals_28d").error
    assert_match "Backend Error", SearchConsoleReport.for("status").error
  end

  test "the refresh job does nothing until Google is connected" do
    with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => nil) do
      stub_http do |calls|
        SearchConsoleRefreshJob.perform_now
        assert_empty calls
      end
    end
  end
end
