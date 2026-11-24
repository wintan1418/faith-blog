# frozen_string_literal: true

require "test_helper"
require_relative "../support/search_indexing_stubs"

# IndexNow: the key, the key file, the payload, batching and what is never sent.
class IndexNowTest < ActiveSupport::TestCase
  include SearchIndexingStubs

  test "enabled only in production unless INDEXNOW_ENABLED says so" do
    with_env("INDEXNOW_ENABLED" => nil) { refute IndexNow.enabled? }
    with_env("INDEXNOW_ENABLED" => "1") { assert IndexNow.enabled? }
    with_env("INDEXNOW_ENABLED" => "0") do
      Rails.env.stub(:production?, true) { refute IndexNow.enabled? }
    end
    with_env("INDEXNOW_ENABLED" => nil) do
      Rails.env.stub(:production?, true) { assert IndexNow.enabled? }
    end
  end

  test "uses INDEXNOW_KEY, else generates one key and keeps it" do
    with_env("INDEXNOW_KEY" => "envkey-123456") { assert_equal "envkey-123456", IndexNow.key }
    with_env("INDEXNOW_KEY" => nil) do
      key = IndexNow.key
      assert_match(/\A[a-f0-9]{32}\z/, key)
      assert_equal key, IndexNow.key
      assert_equal key, SeoSetting["indexnow_key"]
    end
    with_env("INDEXNOW_KEY" => "bad key!") { assert_equal SeoSetting["indexnow_key"], IndexNow.key }
  end

  test "posts the documented JSON payload and logs the submission" do
    with_indexnow do
      stub_http { |calls|
        IndexNow.submit([ "https://brethreign.com/posts/hello", "https://brethreign.com/rooms/prayer" ], trigger: "manual")
        assert_equal 1, calls.size
        call = calls.first
        assert_equal :post, call[:method]
        assert_equal "https://api.indexnow.org/indexnow", call[:url]
        assert_equal "application/json; charset=utf-8", call[:headers]["Content-Type"]
        assert_equal({ "host" => "brethreign.com", "key" => "testkey1234567890",
                       "keyLocation" => "https://brethreign.com/testkey1234567890.txt",
                       "urlList" => [ "https://brethreign.com/posts/hello", "https://brethreign.com/rooms/prayer" ] },
                     JSON.parse(call[:body]))
      }
      log = IndexingSubmission.recent.first
      assert_equal [ "indexnow", "manual", 2, 200 ], [ log.engine, log.trigger, log.urls_count, log.status_code ]
    end
  end

  test "splits more than 10,000 URLs into several requests" do
    urls = (1..10_001).map { |i| "https://brethreign.com/posts/p-#{i}" }
    with_indexnow do
      stub_http do |calls|
        IndexNow.submit(urls)
        assert_equal [ 10_000, 1 ], calls.map { |c| JSON.parse(c[:body])["urlList"].size }
      end
    end
    assert_equal 2, IndexingSubmission.where(engine: "indexnow").count
  end

  test "never sends noindex, private-area or foreign URLs" do
    with_indexnow do
      stub_http do |calls|
        IndexNow.submit([ "https://brethreign.com/join/juwon", "https://brethreign.com/in/juwon", "https://brethreign.com/admin/seo",
                          "http://brethreign.com/posts/x", "https://evil.example/posts/x", "https://brethreign.com/posts/x?ref=1",
                          "https://brethreign.com/posts/ok" ])
        assert_equal [ "https://brethreign.com/posts/ok" ], JSON.parse(calls.first[:body])["urlList"]
      end
    end
  end

  test "a network failure is logged, not raised" do
    with_indexnow do
      SearchIndexing::Http.stub(:request, ->(*) { raise Errno::ECONNREFUSED }) do
        submission = IndexNow.submit([ "https://brethreign.com/posts/x" ]).first
        assert_nil submission.status_code
        refute submission.success?
        assert_match "ECONNREFUSED", submission.response
      end
    end
  end
end
