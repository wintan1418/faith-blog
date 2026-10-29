# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Gemini < Base
        DEFAULT_MODEL = "gemini-2.5-flash"
        THINKING_BUDGET = 512
        ENDPOINT_TEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

        def call(system:, user:, images: [])
          raise Client::ConfigError, "GEMINI_API_KEY missing" if @api_key.to_s.strip.empty?

          uri = URI("#{format(ENDPOINT_TEMPLATE, @model)}?key=#{@api_key}")
          body = {
            systemInstruction: { parts: [ { text: system } ] },
            contents: [ { role: "user", parts: [ { text: user } ] + images.map { |i| { inlineData: { mimeType: i[:mime], data: i[:data] } } } } ],
            generationConfig: {
              temperature: 0.0,
              maxOutputTokens: DEFAULT_MAX_TOKENS + THINKING_BUDGET,
              responseMimeType: "application/json"
            }.merge(thinking_config)
          }

          response = post_json(uri, headers: {}, body: body)
          text = Array(response.dig("candidates", 0, "content", "parts"))
                  .filter_map { |p| p["text"] }
                  .join

          wrap(model: response["modelVersion"] || @model, text: text)
        end

        private

        # Gemini 2.5 "thinks" before answering, and that thinking counts against
        # maxOutputTokens. Unbounded, it could use up the whole limit and return
        # no answer at all. Cap the thinking and leave room for the answer.
        def thinking_config
          @model.to_s.include?("2.5") ? { thinkingConfig: { thinkingBudget: THINKING_BUDGET } } : {}
        end
      end
    end
  end
end
