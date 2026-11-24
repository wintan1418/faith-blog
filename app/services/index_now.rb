# frozen_string_literal: true

# IndexNow (https://www.indexnow.org): one POST tells Bing, Yandex, Seznam,
# Naver and the other participating engines which URLs changed.
#
# The key is ENV["INDEXNOW_KEY"], or one generated once and kept in
# seo_settings. Engines check it at https://brethreign.com/<key>.txt
# (IndexNowKeysController).
#
# On in production only, unless INDEXNOW_ENABLED says otherwise ("1" turns it
# on elsewhere, "0" turns it off in production).
module IndexNow
  ENDPOINT = "https://api.indexnow.org/indexnow"
  MAX_URLS = 10_000 # per request, IndexNow's limit
  KEY_FORMAT = /\A[a-zA-Z0-9-]{8,128}\z/

  module_function

  def enabled?
    flag = ENV["INDEXNOW_ENABLED"].to_s.strip
    return Rails.env.production? if flag.empty?

    %w[1 true yes on].include?(flag.downcase)
  end

  def key
    env_key = ENV["INDEXNOW_KEY"].to_s.strip
    return env_key if env_key.match?(KEY_FORMAT)

    SeoSetting.fetch("indexnow_key") { SecureRandom.hex(16) }
  end

  def key_location(for_key = key)
    "#{SearchIndexing::BASE_URL}/#{for_key}.txt"
  end

  def payload(urls, for_key = key)
    { host: SearchIndexing::HOST, key: for_key, keyLocation: key_location(for_key), urlList: urls }
  end

  # Sends the URLs (in batches of 10,000) and logs each request. Only public
  # brethreign.com URLs are sent. Returns the IndexingSubmission rows.
  def submit(urls, trigger: "auto")
    urls = Array(urls).map(&:to_s).uniq.select { |url| SearchIndexing.public_url?(url) }
    return [] if urls.empty?

    current_key = key
    urls.each_slice(MAX_URLS).map do |batch|
      status, body = post(batch, current_key)
      IndexingSubmission.log!(engine: "indexnow", urls: batch, status_code: status, response: body, trigger: trigger)
    end
  end

  def post(batch, for_key)
    response = SearchIndexing::Http.request(:post, ENDPOINT, payload(batch, for_key).to_json,
                                            "Content-Type" => "application/json; charset=utf-8")
    [ response.status, response.body.to_s.presence || "(empty)" ]
  rescue StandardError => e
    Rails.logger.warn("[IndexNow] request failed: #{e.class}: #{e.message}")
    [ nil, "#{e.class}: #{e.message}" ]
  end
end
