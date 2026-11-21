# frozen_string_literal: true

require "net/http"

# GIFs from Klipy (https://docs.klipy.com), the free GIF API that replaced
# Tenor. Everything here runs on our server so the API key never reaches the
# browser; the GIFs themselves load straight from Klipy's media CDN.
#
# Brethreign is a faith community, so every request asks for Klipy's strictest
# content filter ("high"), and any advertisement item is dropped.
#
# Without KLIPY_API_KEY the feature is off: no GIF button anywhere.
module Klipy
  class Error < StandardError; end

  DEFAULT_BASE_URL = "https://api.klipy.com"
  CONTENT_FILTER = "high" # Klipy accepts off, low, medium, high
  PER_PAGE = 24
  TIMEOUT = 4 # seconds, for connecting and for reading
  MAX_QUERY = 80

  # Klipy's media hosts (docs.klipy.com/network-requirements). A GIF saved with
  # a message or comment must come from one of these, over HTTPS.
  MEDIA_HOST = /\Astatic\d*\.klipy\.com\z/

  module_function

  def configured?
    api_key.present?
  end

  def api_key
    ENV["KLIPY_API_KEY"].to_s.strip
  end

  # Overridable so a local fake can stand in during development.
  def base_url
    ENV["KLIPY_BASE_URL"].presence || DEFAULT_BASE_URL
  end

  def trending(customer_id:, page: 1)
    fetch("trending", customer_id: customer_id, page: page)
  end

  def search(query, customer_id:, page: 1)
    q = query.to_s.squish.first(MAX_QUERY)
    return trending(customer_id: customer_id, page: page) if q.blank?

    fetch("search", q: q, customer_id: customer_id, page: page)
  end

  # True for an https URL on Klipy's media CDN, and nothing else.
  def media_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.to_s.downcase.match?(MEDIA_HOST) && uri.userinfo.nil? &&
      (uri.port.nil? || uri.port == 443)
  rescue URI::InvalidURIError
    false
  end

  # A stable id for a member that tells Klipy nothing about who they are.
  def customer_id_for(user)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "klipy:#{user.id}").first(32)
  end

  def fetch(endpoint, customer_id:, page:, **params)
    raise Error, "Klipy is not configured" unless configured?

    query = params.merge(customer_id: customer_id, page: [ page.to_i, 1 ].max, per_page: PER_PAGE,
                         content_filter: CONTENT_FILTER, format_filter: "gif,webp")
    uri = URI.join(base_url.chomp("/") + "/", "api/v1/#{ERB::Util.url_encode(api_key)}/gifs/#{endpoint}")
    uri.query = URI.encode_www_form(query)

    response = http_get(uri)
    raise Error, "Klipy answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    parse(response.body)
  rescue JSON::ParserError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
    raise Error, "#{e.class}: #{e.message}"
  end

  def http_get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                        open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json"))
    end
  end

  # Only what the picker needs: id, a small preview, the GIF to send, its size
  # and title. Ads (type "ad") and anything not on Klipy's CDN are left out.
  def parse(body)
    json = JSON.parse(body.to_s)
    items = json.dig("data", "data")
    return [] unless items.is_a?(Array)

    items.filter_map { |item| simplify(item) }
  end

  def simplify(item)
    return unless item.is_a?(Hash) && item["type"].to_s == "gif"

    files = item["file"].is_a?(Hash) ? item["file"] : {}
    full = pick(files, %w[md sm hd], %w[gif webp])
    preview = pick(files, %w[sm xs md], %w[webp gif]) || full
    return unless full && media_url?(full["url"]) && media_url?(preview["url"])

    {
      id: item["slug"].presence || item["id"].to_s,
      preview_url: preview["url"],
      url: full["url"],
      width: full["width"].to_i,
      height: full["height"].to_i,
      title: item["title"].to_s.squish.first(140)
    }
  end

  def pick(files, sizes, formats)
    sizes.each do |size|
      formats.each do |format|
        file = files.dig(size, format)
        return file if file.is_a?(Hash) && file["url"].present? && file["width"].to_i.positive? && file["height"].to_i.positive?
      end
    end
    nil
  end
end
