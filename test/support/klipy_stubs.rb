# frozen_string_literal: true

require "minitest/mock"

# Klipy is never called for real in tests: Klipy.http_get is stubbed with a
# canned response shaped like docs.klipy.com's search/trending answer.
module KlipyStubs
  def with_klipy_key(key = "test-klipy-key")
    @klipy_key_was = ENV["KLIPY_API_KEY"] unless defined?(@klipy_key_was)
    ENV["KLIPY_API_KEY"] = key
  end

  def without_klipy_key
    ENV.delete("KLIPY_API_KEY")
  end

  def klipy_response(body, status: 200)
    klass = Net::HTTPResponse::CODE_TO_OBJ[status.to_s] || Net::HTTPOK
    response = klass.new("1.1", status.to_s, "")
    response.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
    response.instance_variable_set(:@read, true)
    response
  end

  def klipy_item(slug, url_base, title:, type: "gif")
    {
      "id" => rand(1_000_000), "slug" => slug, "title" => title, "type" => type,
      "file" => {
        "md" => { "gif" => { "url" => "#{url_base}/md.gif", "width" => 320, "height" => 240 } },
        "sm" => { "webp" => { "url" => "#{url_base}/sm.webp", "width" => 160, "height" => 120 },
                  "gif" => { "url" => "#{url_base}/sm.gif", "width" => 160, "height" => 120 } }
      }
    }
  end

  def klipy_payload
    {
      "result" => true,
      "data" => {
        "data" => [
          klipy_item("praise-hands", "https://static.klipy.com/ii/abc", title: "Praise hands"),
          klipy_item("sponsored", "https://static.klipy.com/ii/ad", title: "Buy now", type: "ad"),
          klipy_item("elsewhere", "https://example.com/ii/x", title: "Elsewhere"),
          klipy_item("amen", "https://static1.klipy.com/ii/def", title: "Amen")
        ],
        "current_page" => 1, "per_page" => 24, "has_next" => false
      }
    }
  end
end
