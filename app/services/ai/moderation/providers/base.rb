# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ai
  module Moderation
    module Providers
      class Base
        DEFAULT_MAX_TOKENS = 600
        DEFAULT_TIMEOUT = 12

        def initialize(model: nil, api_key: nil, timeout: DEFAULT_TIMEOUT)
          @model = model || self.class::DEFAULT_MODEL
          @api_key = api_key
          @timeout = timeout
        end

        # Returns a Hash shaped like:
        #   { "model" => "...", "content" => [ { "type" => "text", "text" => "{...json...}" } ] }
        # so Reviewer's parser can stay provider-agnostic.
        def call(system:, user:)
          raise NotImplementedError
        end

        protected

        def post_json(uri, headers:, body:)
          request = Net::HTTP::Post.new(uri)
          headers.each { |k, v| request[k] = v }
          request["content-type"] = "application/json"
          request.body = JSON.dump(body)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @timeout
          http.read_timeout = @timeout

          response = http.request(request)
          unless response.is_a?(Net::HTTPSuccess)
            raise Client::ApiError, "#{provider_name} #{response.code}: #{response.body}"
          end

          JSON.parse(response.body)
        end

        def provider_name
          self.class.name.demodulize.downcase
        end

        def wrap(model:, text:)
          { "model" => model, "content" => [ { "type" => "text", "text" => text } ] }
        end
      end
    end
  end
end
