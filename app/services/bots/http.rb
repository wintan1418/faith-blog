# frozen_string_literal: true

require "net/http"
require "resolv"

module Bots
  # Small, careful GET for feeds and article pages: https only, public hosts
  # only, short timeouts, a size cap and a few redirects.
  module Http
    class Error < StandardError; end

    USER_AGENT = "BrethreignBot/1.0 (+https://brethreign.com)"
    MAX_BYTES = 3.megabytes
    MAX_REDIRECTS = 3

    module_function

    def get(url, accept: "*/*", redirects: MAX_REDIRECTS)
      uri = URI.parse(url)
      raise Error, "not https: #{url}" unless uri.is_a?(URI::HTTPS)
      raise Error, "private host: #{uri.host}" if private_host?(uri.host)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 8
      http.read_timeout = 12

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = accept

      body = +""
      http.request(request) do |response|
        case response
        when Net::HTTPRedirection
          raise Error, "too many redirects" if redirects.zero?
          return get(URI.join(url, response["location"]).to_s, accept: accept, redirects: redirects - 1)
        when Net::HTTPSuccess
          response.read_body do |chunk|
            body << chunk
            raise Error, "response too large" if body.bytesize > MAX_BYTES
          end
        else
          raise Error, "HTTP #{response.code}"
        end
      end
      body.force_encoding(Encoding::UTF_8)
      body.valid_encoding? ? body : body.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace)
    rescue URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Zlib::Error => e
      raise Error, "#{e.class}: #{e.message}"
    end

    def private_host?(host)
      return true if host.blank? || host == "localhost"

      Resolv.getaddresses(host).any? do |address|
        ip = IPAddr.new(address)
        ip.private? || ip.loopback? || ip.link_local? || address == "0.0.0.0"
      end
    rescue IPAddr::InvalidAddressError
      true
    end
  end
end
