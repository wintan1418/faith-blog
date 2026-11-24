# frozen_string_literal: true

require "test_helper"
require_relative "../../support/search_indexing_stubs"

# Admin → Search & indexing: who may see it, how it looks with and without
# Google, and what its buttons send.
class Admin::SeoControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SearchIndexingStubs

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @admin = create_member("seo_admin_#{SecureRandom.hex(3)}", role: :admin)
    @room = Room.create!(name: "Seo Admin Room #{SecureRandom.hex(3)}", description: "x", is_public: true)
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def seed_reports
    SearchConsoleReport.store!("status", data: { "ok" => true })
    SearchConsoleReport.store!("totals_28d", data: { "clicks" => 1234, "impressions" => 56_789, "ctr" => 0.0217, "position" => 12.34 })
    SearchConsoleReport.store!("queries_28d", data: { "rows" => [ { "key" => "christian community app", "clicks" => 40, "impressions" => 900, "ctr" => 0.044, "position" => 6.2 } ] })
    SearchConsoleReport.store!("pages_28d", data: { "rows" => [ { "key" => "https://brethreign.com/blog", "clicks" => 30, "impressions" => 700, "ctr" => 0.04, "position" => 8.1 } ] })
    SearchConsoleReport.store!("pages_seen_3m", data: { "count" => 321 })
    SearchConsoleReport.store!("sitemaps", data: { "sitemaps" => [ { "path" => "https://brethreign.com/sitemap.xml", "lastSubmitted" => "2026-11-20T04:00:00Z",
                                                                     "lastDownloaded" => "2026-11-21T09:00:00Z", "errors" => "0", "warnings" => "0",
                                                                     "contents" => [ { "type" => "web", "submitted" => "812" } ] } ] })
  end

  test "members and signed-out visitors can't open it" do
    get admin_seo_path
    assert_response :redirect

    sign_in create_member("seo_member_#{SecureRandom.hex(3)}")
    get admin_seo_path
    assert_redirected_to root_path
    post index_now_admin_seo_path, params: { url: "https://brethreign.com/rooms/#{@room.slug}" }
    assert_redirected_to root_path
    assert_equal 0, IndexingSubmission.count
  end

  test "without Google it explains how to connect and still shows IndexNow" do
    sign_in @admin
    with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => nil) { get admin_seo_path }
    assert_response :success
    assert_select "h1", "Search & indexing"
    assert_select "#connect-google", /Add user/
    assert_select "#connect-google code", "GOOGLE_SEARCH_CONSOLE_CREDENTIALS"
    assert_select "#indexnow"
    assert_select ".admin-side-link.is-active", /Search &amp; indexing|Search & indexing/
    assert_select "#inspect", false
  end

  test "with Google it shows the stored numbers, tables, sitemap and inspection" do
    sign_in @admin
    seed_reports
    url = "https://brethreign.com/rooms/#{@room.slug}"
    with_google do
      stub_google(->(*) { [ 200, { inspectionResult: { "inspectionResultLink" => "https://search.google.com/x",
                                                        "indexStatusResult" => { "verdict" => "PASS", "coverageState" => "Submitted and indexed",
                                                                                 "lastCrawlTime" => "2026-11-22T10:00:00Z",
                                                                                 "googleCanonical" => url, "userCanonical" => url,
                                                                                 "pageFetchState" => "SUCCESSFUL" } } } ] }) do |calls|
        get admin_seo_path
        assert_empty calls, "the page reads the database, not Google"
        assert_response :success
        assert_select ".adash-kpi__value", "1,234"
        assert_select ".adash-kpi__value", "56,789"
        assert_select ".adash-kpi__value", "12.3"
        assert_select ".adash-kpi__value", "321"
        assert_select "td", "christian community app"
        assert_select "#sitemaps", /812 web URLs/
        assert_select "#connect-google", false

        post inspect_url_admin_seo_path, params: { url: url }
        follow_redirect!
        assert_select "#inspect .aseo-facts", /Submitted and indexed/
        assert_select "#inspect a[href='https://search.google.com/x']", "open it in Search Console"
        assert_select "#inspect", /no public API for “Request indexing”/
      end
    end
  end

  test "inspect refuses addresses outside the site" do
    sign_in @admin
    with_google do
      stub_google do |calls|
        post inspect_url_admin_seo_path, params: { url: "https://example.com/" }
        assert_empty calls
      end
    end
    follow_redirect!
    assert_match "public https://brethreign.com address", response.body
  end

  test "Refresh now and Resubmit sitemap" do
    sign_in @admin
    with_google do
      assert_enqueued_with(job: SearchConsoleRefreshJob) { post refresh_admin_seo_path }
      stub_google do |calls|
        post sitemap_admin_seo_path
        assert_equal :put, calls.last[:method]
      end
    end
    assert_equal "google_sitemap", IndexingSubmission.recent.first.engine
    assert_equal "manual", IndexingSubmission.recent.first.trigger
  end

  test "Send page: public pages go to IndexNow, private and anonymous ones never" do
    sign_in @admin
    author = create_member("seo_writer_#{SecureRandom.hex(3)}")
    anon = Post.create!(user: author, room: @room, title: "Hidden", content: "x", status: :published,
                        moderation_status: :approved, anonymous: true)
    private_room = Room.create!(name: "Seo Private #{SecureRandom.hex(3)}", description: "x", is_public: false)

    with_indexnow do
      stub_http do |calls|
        post index_now_admin_seo_path, params: { url: "https://brethreign.com/posts/#{anon.slug}" }
        post index_now_admin_seo_path, params: { url: "https://brethreign.com/rooms/#{private_room.slug}" }
        post index_now_admin_seo_path, params: { url: "https://brethreign.com/join/#{author.username}" }
        assert_empty calls

        post index_now_admin_seo_path, params: { url: "https://brethreign.com/rooms/#{@room.slug}" }
        assert_equal [ "https://brethreign.com/rooms/#{@room.slug}" ], JSON.parse(calls.last[:body])["urlList"]
        follow_redirect!
        assert_match "Sent 1 page to IndexNow", response.body

        post index_now_admin_seo_path, params: { scope: "recent" }
        sent = JSON.parse(calls.last[:body])["urlList"]
        assert_includes sent, "https://brethreign.com/rooms/#{@room.slug}"
        refute_includes sent, "https://brethreign.com/posts/#{anon.slug}"
        refute_includes sent, "https://brethreign.com/rooms/#{private_room.slug}"
      end
    end
    get admin_seo_path
    assert_select "#log td", "Manual"
  end

  test "Send page is refused outside production" do
    sign_in @admin
    with_env("INDEXNOW_ENABLED" => "0") do
      stub_http do |calls|
        post index_now_admin_seo_path, params: { url: "https://brethreign.com/rooms/#{@room.slug}" }
        assert_empty calls
      end
    end
    follow_redirect!
    assert_match "only runs in production", response.body
  end
end

# /<key>.txt for IndexNow's ownership check.
class IndexNowKeyFileTest < ActionDispatch::IntegrationTest
  include SearchIndexingStubs

  test "serves the key as plain text and 404s other names" do
    with_env("INDEXNOW_KEY" => "abcdef0123456789") do
      get "/abcdef0123456789.txt"
      assert_response :success
      assert_equal "abcdef0123456789", response.body
      assert_match "text/plain", response.media_type

      get "/0123456789abcdef.txt"
      assert_response :not_found
    end
  end
end
