# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Anthropic < Base
        DEFAULT_MODEL = "claude-haiku-4-5-20251001"
        ANTHROPIC_VERSION = "2023-06-01"
        ENDPOINT = URI("https://api.anthropic.com/v1/messages")

        def call(system:, user:)
          raise Client::ConfigError, "ANTHROPIC_API_KEY missing" if @api_key.to_s.strip.empty?

          body = {
            model: @model,
            max_tokens: DEFAULT_MAX_TOKENS,
            system: system,
            messages: [ { role: "user", content: user } ]
          }

          response = post_json(
            ENDPOINT,
            headers: {
              "x-api-key" => @api_key,
              "anthropic-version" => ANTHROPIC_VERSION
            },
            body: body
          )

          text = Array(response["content"]).filter_map { |p| p["text"] if p["type"] == "text" }.join
          wrap(model: response["model"] || @model, text: text)
        end
      end
    end
  end
end
