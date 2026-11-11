# frozen_string_literal: true

module Ai
  module Office
    module Providers
      # OpenAI Chat Completions with function calling. If the default model
      # isn't available to the key, the next one in FALLBACK_MODELS is tried.
      class Openai < Base
        DEFAULT_MODEL = "gpt-5.5"
        FALLBACK_MODELS = %w[gpt-5.1 gpt-4.1].freeze
        ENDPOINT = URI("https://api.openai.com/v1/chat/completions")

        def display_name = "OpenAI"

        def chat(system:, messages:, tools:)
          require_key!

          candidates = [ model, *FALLBACK_MODELS ].uniq
          begin
            current = candidates.first
            response = request(current, system, messages, tools)
          rescue Client::ApiError => e
            raise unless model_unavailable?(e) && candidates.size > 1

            Rails.logger.warn("[Office] #{current} unavailable, trying #{candidates.second}")
            candidates.shift
            retry
          end

          message = response.dig("choices", 0, "message") || {}
          calls = Array(message["tool_calls"]).map do |c|
            { "id" => c["id"], "name" => c.dig("function", "name"), "input" => parse_args(c.dig("function", "arguments")) }
          end
          text = message["content"].to_s
          text = "I can't help with that one. Could you put it another way?" if text.blank? && message["refusal"].present?

          Reply.new(text: text, tool_calls: calls, model: response["model"] || current,
                    raw: nil, stop_reason: response.dig("choices", 0, "finish_reason"))
        end

        private

        def request(model_id, system, messages, tools)
          body = {
            model: model_id,
            max_completion_tokens: MAX_TOKENS,
            messages: [ { role: "system", content: system } ] + convert(messages),
            tools: tools.map { |t| { type: "function", function: { name: t[:name], description: t[:description], parameters: t[:parameters] } } }
          }
          post_json(ENDPOINT, headers: { "authorization" => "Bearer #{@api_key}" }, body: body)
        end

        def model_unavailable?(error)
          error.status.in?([ 400, 403, 404 ]) && error.message.match?(/model/i) && ENV["OFFICE_MODEL"].blank?
        end

        def parse_args(json)
          JSON.parse(json.to_s.presence || "{}")
        rescue JSON::ParserError
          {}
        end

        def convert(messages)
          messages.filter_map do |m|
            case m[:role]
            when :user
              { role: "user", content: m[:text].to_s } if m[:text].present?
            when :assistant
              calls = Array(m[:tool_calls])
              next if m[:text].blank? && calls.empty?

              msg = { role: "assistant", content: m[:text].presence }
              if calls.any?
                msg[:tool_calls] = calls.map do |c|
                  { id: c["id"], type: "function", function: { name: c["name"], arguments: JSON.dump(c["input"] || {}) } }
                end
              end
              msg
            when :tool
              { role: "tool", tool_call_id: m[:tool_call_id], content: JSON.dump(m[:result]) }
            end
          end
        end
      end
    end
  end
end
