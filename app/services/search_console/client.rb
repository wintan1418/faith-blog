# frozen_string_literal: true

require "openssl"
require "base64"

module SearchConsole
  # A tiny Search Console API client. Authenticates as a service account with
  # a signed JWT (RS256, stdlib OpenSSL) exchanged for an access token.
  class Client
    SCOPE = "https://www.googleapis.com/auth/webmasters"
    DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token"
    WEBMASTERS = "https://www.googleapis.com/webmasters/v3"
    INSPECT_URL = "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect"
    TOKEN_LIFETIME = 3600

    # Access tokens are reused until a minute before they expire (per process).
    @tokens = {}
    @tokens_lock = Mutex.new
    class << self
      attr_reader :tokens, :tokens_lock
    end

    attr_reader :site

    def initialize(credentials:, site:)
      @email = credentials.fetch("client_email")
      @private_key = credentials.fetch("private_key")
      @token_uri = credentials["token_uri"].presence || DEFAULT_TOKEN_URI
      @site = site
    end

    # sitemaps.list
    def sitemaps
      get("#{site_base}/sitemaps").fetch("sitemap", [])
    end

    # sitemaps.submit (an empty 200 on success)
    def submit_sitemap(feed_url = SITEMAP_URL)
      call(:put, "#{site_base}/sitemaps/#{CGI.escape(feed_url)}")
      true
    end

    # searchanalytics.query: rows of { keys, clicks, impressions, ctr, position }
    def search_analytics(start_date:, end_date:, dimensions: [], row_limit: 25)
      body = { startDate: start_date.iso8601, endDate: end_date.iso8601, dimensions: dimensions,
               rowLimit: row_limit, dataState: "final" }
      call(:post, "#{site_base}/searchAnalytics/query", body).fetch("rows", [])
    end

    # urlInspection.index.inspect: the inspectionResult hash
    def inspect_url(url)
      call(:post, INSPECT_URL, { inspectionUrl: url, siteUrl: site, languageCode: "en-US" }).fetch("inspectionResult", {})
    end

    # The signed assertion sent to Google's token endpoint.
    def jwt_assertion(now = Time.now.to_i)
      header = { alg: "RS256", typ: "JWT" }
      claims = { iss: @email, scope: SCOPE, aud: @token_uri, iat: now, exp: now + TOKEN_LIFETIME }
      signing_input = [ header, claims ].map { |part| base64url(part.to_json) }.join(".")
      signature = OpenSSL::PKey::RSA.new(@private_key).sign(OpenSSL::Digest.new("SHA256"), signing_input)
      "#{signing_input}.#{base64url(signature)}"
    rescue OpenSSL::PKey::PKeyError
      raise Error, "The service account private key couldn't be read"
    end

    def access_token
      cache_key = [ @email, @token_uri ]
      cached = self.class.tokens_lock.synchronize { self.class.tokens[cache_key] }
      return cached[:token] if cached && cached[:expires_at] > Time.now + 60

      token, expires_in = fetch_token
      self.class.tokens_lock.synchronize do
        self.class.tokens[cache_key] = { token: token, expires_at: Time.now + expires_in.to_i }
      end
      token
    end

    def self.reset_tokens!
      tokens_lock.synchronize { tokens.clear }
    end

    private

    def site_base
      "#{WEBMASTERS}/sites/#{CGI.escape(site)}"
    end

    def fetch_token
      body = URI.encode_www_form(grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt_assertion)
      response = SearchIndexing::Http.request(:post, @token_uri, body, "Content-Type" => "application/x-www-form-urlencoded")
      data = response.json
      unless response.success? && data["access_token"].present?
        raise Error, "Google sign-in failed (#{response.status}): #{data['error_description'] || data['error'] || 'no token'}"
      end

      [ data["access_token"], data["expires_in"] || TOKEN_LIFETIME ]
    end

    def get(url)
      call(:get, url)
    end

    def call(method, url, body = nil)
      headers = { "Authorization" => "Bearer #{access_token}", "Accept" => "application/json" }
      headers["Content-Type"] = "application/json" if body
      response = SearchIndexing::Http.request(method, url, body&.to_json, headers)
      return response.json if response.success?

      message = response.json.dig("error", "message").presence || "HTTP #{response.status}"
      raise Error, "Search Console said: #{message}"
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Error, "Couldn't reach Google (#{e.class})"
    end

    def base64url(data)
      Base64.urlsafe_encode64(data, padding: false)
    end
  end
end
