# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ai
  module Office
    module Providers
      # A provider turns the Office's provider-neutral history into one model
      # call and hands back an Ai::Office::Reply.
      #
      # History entries (Hashes):
      #   { role: :user, text: "..." }
      #   { role: :assistant, text: "...", tool_calls: [{ "id", "name", "input" }], raw: { "provider", "content" } }
      #   { role: :tool, tool_call_id: "...", name: "...", result: { ... } }
      # Tools: [{ name:, description:, parameters: <JSON schema> }]
      class Base
        TIMEOUT = 180 # runs in a background job; long replies and slow tool turns are fine
        MAX_TOKENS = 8_000

        attr_reader :model

        def initialize(api_key: nil, model: nil)
          @api_key = api_key
          @model = model || self.class::DEFAULT_MODEL
        end

        def chat(system:, messages:, tools:)
          raise NotImplementedError
        end

        def display_name = self.class.name.demodulize

        def provider_key = self.class.name.demodulize.downcase

        protected

        def require_key!
          raise Client::Error, "#{display_name} API key missing" if @api_key.to_s.strip.empty?
        end

        def post_json(uri, headers:, body:, timeout: TIMEOUT)
          request = Net::HTTP::Post.new(uri)
          headers.each { |k, v| request[k] = v }
          request["content-type"] = "application/json"
          request.body = JSON.dump(body)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 15
          http.read_timeout = timeout

          response = begin
            http.request(request)
          rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
            raise Client::ApiError, "#{display_name} unreachable: #{e.class}: #{e.message}"
          end
          unless response.is_a?(Net::HTTPSuccess)
            raise Client::ApiError.new("#{display_name} #{response.code}: #{response.body.to_s.truncate(600)}", status: response.code.to_i)
          end

          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise Client::ApiError, "#{display_name} sent a non-JSON reply: #{e.message}"
        end

        # The raw content to replay is only usable by the provider that made it.
        def own_raw(entry)
          raw = entry[:raw]
          raw["content"] if raw.is_a?(Hash) && raw["provider"] == provider_key && raw["model"] == model
        end
      end
    end
  end
end
