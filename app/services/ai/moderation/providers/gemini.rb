# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Gemini < Base
        DEFAULT_MODEL = "gemini-2.5-flash"
        ENDPOINT_TEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

        def call(system:, user:)
          raise Client::ConfigError, "GEMINI_API_KEY missing" if @api_key.to_s.strip.empty?

          uri = URI("#{format(ENDPOINT_TEMPLATE, @model)}?key=#{@api_key}")
          body = {
            systemInstruction: { parts: [ { text: system } ] },
            contents: [ { role: "user", parts: [ { text: user } ] } ],
            generationConfig: {
              temperature: 0.0,
              maxOutputTokens: DEFAULT_MAX_TOKENS,
              responseMimeType: "application/json"
            }
          }

          response = post_json(uri, headers: {}, body: body)
          text = Array(response.dig("candidates", 0, "content", "parts"))
                  .filter_map { |p| p["text"] }
                  .join

          wrap(model: response["modelVersion"] || @model, text: text)
        end
      end
    end
  end
end
