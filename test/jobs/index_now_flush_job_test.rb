# frozen_string_literal: true

require "test_helper"
require_relative "../support/search_indexing_stubs"

# The batch flush and the nightly sweep.
class IndexNowFlushJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SearchIndexingStubs

  def add_pending(*urls)
    urls.each { |url| IndexingPendingUrl.create!(url: url) }
  end

  test "sends everything waiting in one request and clears the list" do
    with_indexnow do
      add_pending("https://brethreign.com/posts/a", "https://brethreign.com/posts/b")
      stub_http do |calls|
        IndexNowFlushJob.perform_now
        assert_equal 1, calls.size
        assert_equal %w[https://brethreign.com/posts/a https://brethreign.com/posts/b], JSON.parse(calls.first[:body])["urlList"]
      end
      assert_equal 0, IndexingPendingUrl.count
    end
  end

  test "keeps URLs for later when IndexNow is busy or down" do
    with_indexnow do
      add_pending("https://brethreign.com/posts/a")
      stub_http_answering(429, "slow down") { IndexNowFlushJob.perform_now }
      assert_equal 1, IndexingPendingUrl.count
      assert_equal 429, IndexingSubmission.recent.first.status_code
    end
  end

  test "does nothing when IndexNow is off" do
    with_env("INDEXNOW_ENABLED" => "0") do
      add_pending("https://brethreign.com/posts/a")
      stub_http do |calls|
        IndexNowFlushJob.perform_now
        assert_empty calls
      end
    end
  end

  test "queueing a burst of changes starts one timer" do
    with_indexnow do
      assert_enqueued_jobs 1, only: IndexNowFlushJob do
        SearchIndexing.queue([ "https://brethreign.com/posts/a" ])
        SearchIndexing.queue([ "https://brethreign.com/posts/b", "https://brethreign.com/posts/a" ])
      end
      assert_equal 2, IndexingPendingUrl.count
    end
  end

  test "concurrency keys accept any arguments" do
    assert_nothing_raised { IndexNowFlushJob.new.concurrency_key }
    assert_nothing_raised { IndexNowFlushJob.new("nightly").concurrency_key }
    assert_nothing_raised { SearchConsoleRefreshJob.new.concurrency_key }
    assert_nothing_raised { SearchConsoleRefreshJob.new(1, foo: 2).concurrency_key }
  end

  test "nightly: sitemap to Google when connected, then the day's changes to IndexNow" do
    room = Room.create!(name: "Nightly Room #{SecureRandom.hex(3)}", description: "x", is_public: true)
    IndexingPendingUrl.delete_all
    with_indexnow do
      with_google do
        stub_google do |calls|
          SearchIndexingNightlyJob.perform_now
          sitemap = calls.find { |c| c[:method] == :put }
          assert_equal "https://www.googleapis.com/webmasters/v3/sites/sc-domain%3Abrethreign.com/sitemaps/https%3A%2F%2Fbrethreign.com%2Fsitemap.xml", sitemap[:url]
          indexnow = calls.find { |c| c[:url] == IndexNow::ENDPOINT }
          assert_includes JSON.parse(indexnow[:body])["urlList"], "https://brethreign.com/rooms/#{room.slug}"
        end
      end
    end
    assert_equal %w[google_sitemap indexnow], IndexingSubmission.where(trigger: "nightly").order(:id).pluck(:engine)
    assert_equal 0, IndexingPendingUrl.count
  end

  test "nightly without Google or IndexNow sends nothing" do
    with_env("INDEXNOW_ENABLED" => "0", "GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => nil) do
      stub_http do |calls|
        SearchIndexingNightlyJob.perform_now
        assert_empty calls
      end
    end
  end
end
