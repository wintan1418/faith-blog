# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ai
  module Moderation
    class Client
      class Error < StandardError; end
      class ConfigError < Error; end
      class ApiError < Error; end

      ENDPOINT = URI("https://api.anthropic.com/v1/messages")
      ANTHROPIC_VERSION = "2023-06-01"
      DEFAULT_MODEL = "claude-haiku-4-5-20251001"
      DEFAULT_MAX_TOKENS = 600
      DEFAULT_TIMEOUT = 12

      def self.stub?
        ENV["AI_MODERATION_STUB"] == "1" || ENV["ANTHROPIC_API_KEY"].to_s.strip.empty?
      end

      def self.call(system:, user:, model: DEFAULT_MODEL)
        new(model: model).call(system: system, user: user)
      end

      def initialize(model: DEFAULT_MODEL, api_key: ENV["ANTHROPIC_API_KEY"], timeout: DEFAULT_TIMEOUT)
        @model = model
        @api_key = api_key
        @timeout = timeout
      end

      def call(system:, user:)
        return stub_response(user) if self.class.stub?

        request = Net::HTTP::Post.new(ENDPOINT)
        request["content-type"] = "application/json"
        request["x-api-key"] = @api_key
        request["anthropic-version"] = ANTHROPIC_VERSION
        request.body = JSON.dump(
          model: @model,
          max_tokens: DEFAULT_MAX_TOKENS,
          system: system,
          messages: [ { role: "user", content: user } ]
        )

        http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
        http.use_ssl = true
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        response = http.request(request)
        raise ApiError, "anthropic #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      private

      # Deterministic stub for development/test. No external call.
      # Looks for obvious red-flag tokens so tests can assert flow without live AI.
      def stub_response(user)
        flagged_keywords = %w[kill suicide bomb scam phish stupid hate]
        match = flagged_keywords.find { |w| user.to_s.downcase.include?(w) }

        if match
          severity = (match == "kill" || match == "bomb" || match == "suicide") ? "high" : "medium"
          payload = {
            safe: false,
            severity: severity,
            categories: [ infer_category(match) ],
            score: severity == "high" ? 0.92 : 0.65,
            summary: "Stub flagged content matched keyword '#{match}'.",
            recommended_action: Policy.severity_to_action(severity)
          }
        else
          payload = {
            safe: true,
            severity: "none",
            categories: [],
            score: 0.05,
            summary: "Stub review found no obvious violations.",
            recommended_action: "allow"
          }
        end

        {
          "id" => "stub_#{SecureRandom.hex(6)}",
          "model" => "stub",
          "content" => [ { "type" => "text", "text" => JSON.dump(payload) } ]
        }
      end

      def infer_category(word)
        case word
        when "kill", "bomb"        then "violence"
        when "suicide"             then "self_harm"
        when "scam", "phish"       then "scam"
        when "hate"                then "hate"
        when "stupid"              then "harassment"
        else "heated_language"
        end
      end
    end
  end
end
