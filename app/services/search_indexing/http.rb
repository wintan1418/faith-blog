# frozen_string_literal: true

require "net/http"

# The one place search-indexing code talks to the network, so tests can stub
# SearchIndexing::Http.request and never reach IndexNow or Google.
module SearchIndexing
  module Http
    Response = Data.define(:status, :body) do
      def success? = status.to_i.between?(200, 299)

      def json
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end
    end

    TIMEOUT = 15 # seconds, for connecting and for reading

    module_function

    # method: :get, :post or :put. body: a String (already encoded) or nil.
    def request(method, url, body = nil, headers = {})
      uri = URI.parse(url)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
      req = klass.new(uri)
      headers.each { |name, value| req[name] = value }
      req.body = body if body

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.request(req) }
      Response.new(status: res.code.to_i, body: res.body.to_s)
    end
  end
end
