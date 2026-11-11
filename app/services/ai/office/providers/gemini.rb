# frozen_string_literal: true

require "securerandom"

module Ai
  module Office
    module Providers
      # Gemini generateContent with function declarations. The model's parts
      # (with their thought signatures) are kept and replayed unchanged.
      class Gemini < Base
        DEFAULT_MODEL = "gemini-2.5-pro"
        ENDPOINT_TEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

        def chat(system:, messages:, tools:)
          require_key!

          body = {
            systemInstruction: { parts: [ { text: system } ] },
            contents: convert(messages),
            tools: [ { functionDeclarations: tools.map { |t| { name: t[:name], description: t[:description], parameters: t[:parameters] } } } ],
            generationConfig: { maxOutputTokens: MAX_TOKENS }
          }
          uri = URI(format(ENDPOINT_TEMPLATE, model))
          response = post_json(uri, headers: { "x-goog-api-key" => @api_key }, body: body)

          parts = Array(response.dig("candidates", 0, "content", "parts"))
          text = parts.filter_map { |p| p["text"] unless p["thought"] }.join
          calls = parts.filter_map do |p|
            call = p["functionCall"] or next
            { "id" => call["id"].presence || "call_#{SecureRandom.hex(6)}", "name" => call["name"], "input" => call["args"] || {} }
          end

          Reply.new(text: text, tool_calls: calls, model: response["modelVersion"] || model,
                    raw: { "provider" => provider_key, "model" => model, "content" => parts },
                    stop_reason: response.dig("candidates", 0, "finishReason"))
        end

        private

        def convert(messages)
          messages.each_with_object([]) do |m, out|
            case m[:role]
            when :user
              push(out, "user", [ { text: m[:text].to_s } ]) if m[:text].present?
            when :assistant
              parts = own_raw(m) || build_parts(m)
              out << { role: "model", parts: parts } if parts.any?
            when :tool
              push(out, "user", [ { functionResponse: { name: m[:name], response: { result: m[:result] } } } ])
            end
          end
        end

        def build_parts(m)
          parts = []
          parts << { text: m[:text] } if m[:text].present?
          Array(m[:tool_calls]).each { |c| parts << { functionCall: { name: c["name"], args: c["input"] || {} } } }
          parts
        end

        def push(out, role, parts)
          if out.last && out.last[:role] == role
            out.last[:parts] += parts
          else
            out << { role: role, parts: parts }
          end
        end
      end
    end
  end
end
