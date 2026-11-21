# frozen_string_literal: true

require "test_helper"

# The Klipy client: strictest rating, key kept in the server-side request,
# ads and off-CDN items dropped, and the media URL allowlist.
class KlipyTest < ActiveSupport::TestCase
  include KlipyStubs

  setup { with_klipy_key }
  teardown { without_klipy_key }

  test "asks for the strictest content filter and only what the picker needs" do
    seen = nil
    results = Klipy.stub(:http_get, ->(uri) { seen = uri; klipy_response(klipy_payload) }) do
      Klipy.search("  praise   God ", customer_id: "abc")
    end

    params = Rack::Utils.parse_query(seen.query)
    assert_equal "high", params["content_filter"]
    assert_equal "praise God", params["q"]
    assert_equal "abc", params["customer_id"]
    assert_equal "/api/v1/test-klipy-key/gifs/search", seen.path
    assert_equal "api.klipy.com", seen.host

    assert_equal 2, results.size, "the ad and the off-CDN item are dropped"
    first = results.first
    assert_equal %i[height id preview_url title url width], first.keys.sort
    assert_equal "https://static.klipy.com/ii/abc/md.gif", first[:url]
    assert_equal "https://static.klipy.com/ii/abc/sm.webp", first[:preview_url]
    assert_equal [ 320, 240 ], [ first[:width], first[:height] ]
    assert_equal "Praise hands", first[:title]
  end

  test "an empty search shows trending" do
    seen = nil
    Klipy.stub(:http_get, ->(uri) { seen = uri; klipy_response(klipy_payload) }) { Klipy.search(" ", customer_id: "abc") }
    assert_equal "/api/v1/test-klipy-key/gifs/trending", seen.path
    assert_equal "high", Rack::Utils.parse_query(seen.query)["content_filter"]
  end

  test "upstream failures become Klipy::Error" do
    Klipy.stub(:http_get, ->(_uri) { klipy_response("{}", status: 500) }) do
      assert_raises(Klipy::Error) { Klipy.trending(customer_id: "abc") }
    end
    Klipy.stub(:http_get, ->(_uri) { raise Net::ReadTimeout }) do
      assert_raises(Klipy::Error) { Klipy.trending(customer_id: "abc") }
    end
    Klipy.stub(:http_get, ->(_uri) { klipy_response("not json") }) do
      assert_raises(Klipy::Error) { Klipy.trending(customer_id: "abc") }
    end
  end

  test "is off without a key" do
    without_klipy_key
    assert_not Klipy.configured?
    assert_raises(Klipy::Error) { Klipy.trending(customer_id: "abc") }
  end

  test "media URL allowlist: only https on Klipy's CDN" do
    assert Klipy.media_url?("https://static.klipy.com/ii/a/b.gif")
    assert Klipy.media_url?("https://static1.klipy.com/ii/a/b.webp")
    assert Klipy.media_url?("https://static2.klipy.com/x.gif?x=1")

    [
      "http://static.klipy.com/ii/a/b.gif",
      "https://static.klipy.com.evil.example/a.gif",
      "https://evilstatic.klipy.com/a.gif",
      "https://klipy.com/a.gif",
      "https://api.klipy.com/a.gif",
      "https://user@static.klipy.com/a.gif",
      "https://static.klipy.com:8443/a.gif",
      "javascript:alert(1)",
      "//static.klipy.com/a.gif",
      "https://example.com/static.klipy.com/a.gif",
      "not a url",
      ""
    ].each { |url| assert_not Klipy.media_url?(url), url }
  end

  test "the customer id is stable and doesn't reveal the member" do
    user = create_member("gif_fan")
    id = Klipy.customer_id_for(user)
    assert_equal id, Klipy.customer_id_for(user)
    assert_not_equal user.id.to_s, id
    assert_not_equal id, Klipy.customer_id_for(create_member("other_fan"))
    assert_equal 32, id.length
  end
end
