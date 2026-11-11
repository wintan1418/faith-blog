# frozen_string_literal: true

module Ai
  module Office
    module Providers
      # Claude through the Messages API. Thinking stays on (adaptive) on current
      # models; the reply's full content, thinking blocks included, is stored
      # and replayed unchanged so tool turns continue cleanly.
      class Anthropic < Base
        DEFAULT_MODEL = "claude-opus-5-5"
        ENDPOINT = URI("https://api.anthropic.com/v1/messages")
        VERSION = "2023-06-01"
        MAX_TOKENS = 16_000

        def display_name = "Claude"

        def chat(system:, messages:, tools:)
          require_key!

          body = {
            model: model,
            max_tokens: MAX_TOKENS,
            system: [ { type: "text", text: system, cache_control: { type: "ephemeral" } } ],
            messages: convert(messages),
            tools: tools.map { |t| { name: t[:name], description: t[:description], input_schema: t[:parameters] } }
          }
          body[:output_config] = { effort: ENV.fetch("OFFICE_EFFORT", "medium") } if effort_supported?

          response = post_json(ENDPOINT, headers: { "x-api-key" => @api_key, "anthropic-version" => VERSION }, body: body)
          content = Array(response["content"])
          text = content.filter_map { |b| b["text"] if b["type"] == "text" }.join("\n\n")
          text = "I can't help with that one. Could you put it another way?" if response["stop_reason"] == "refusal" && text.blank?
          calls = content.select { |b| b["type"] == "tool_use" }
                         .map { |b| { "id" => b["id"], "name" => b["name"], "input" => b["input"] || {} } }

          Reply.new(text: text, tool_calls: calls, model: response["model"] || model,
                    raw: { "provider" => provider_key, "model" => model, "content" => content },
                    stop_reason: response["stop_reason"])
        end

        private

        # Effort is understood by Claude 4.6 and later; older ids would reject it.
        def effort_supported? = model.match?(/claude-(opus|sonnet|haiku|fable|mythos)-(5|4-[6-9])/)

        def convert(messages)
          messages.each_with_object([]) do |m, out|
            case m[:role]
            when :user
              push(out, "user", [ { type: "text", text: m[:text].to_s } ]) if m[:text].present?
            when :assistant
              content = own_raw(m) || build_assistant(m)
              out << { role: "assistant", content: content } if content.any?
            when :tool
              block = { type: "tool_result", tool_use_id: m[:tool_call_id], content: JSON.dump(m[:result]) }
              block[:is_error] = true if m[:result].is_a?(Hash) && m[:result]["error"].present?
              push(out, "user", [ block ])
            end
          end
        end

        def build_assistant(m)
          blocks = []
          blocks << { type: "text", text: m[:text] } if m[:text].present?
          Array(m[:tool_calls]).each { |c| blocks << { type: "tool_use", id: c["id"], name: c["name"], input: c["input"] || {} } }
          blocks
        end

        # Tool results and the founder's next words share one user turn.
        def push(out, role, blocks)
          if out.last && out.last[:role] == role
            out.last[:content] += blocks
          else
            out << { role: role, content: blocks }
          end
        end
      end
    end
  end
end
