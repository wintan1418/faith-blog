# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Openai < Base
        DEFAULT_MODEL = "gpt-4o-mini"
        ENDPOINT = URI("https://api.openai.com/v1/chat/completions")

        def call(system:, user:, images: [])
          raise Client::ConfigError, "OPENAI_API_KEY missing" if @api_key.to_s.strip.empty?

          body = {
            model: @model,
            temperature: 0.0,
            max_tokens: DEFAULT_MAX_TOKENS,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: system },
              { role: "user", content: images.empty? ? user : [ { type: "text", text: user } ] +
                images.map { |i| { type: "image_url", image_url: { url: "data:#{i[:mime]};base64,#{i[:data]}" } } } }
            ]
          }

          response = post_json(
            ENDPOINT,
            headers: { "authorization" => "Bearer #{@api_key}" },
            body: body
          )

          text = response.dig("choices", 0, "message", "content").to_s
          wrap(model: response["model"] || @model, text: text)
        end
      end
    end
  end
end
