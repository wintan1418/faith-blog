# frozen_string_literal: true

module Ai
  module Office
    # One assistant turn: ask the model, run any tools it calls, feed the
    # results back, and repeat until it answers in words (at most
    # MAX_TOOL_ROUNDS rounds of tools). Every message it saves appears in the
    # thread straight away through Turbo Streams.
    class Runner
      MAX_TOOL_ROUNDS = 6
      HISTORY_LIMIT = 40
      FRIENDLY_ERROR = "Sorry, I couldn't finish that reply. Something went wrong reaching the AI. Press Try again, or send your message once more."

      def initialize(conversation, provider: Client.build)
        @conversation = conversation
        @provider = provider
        @context = Tools::Context.new(user: conversation.user, conversation: conversation)
      end

      def run
        rounds = 0
        loop do
          reply = @provider.chat(system: system_prompt, messages: history, tools: Tools.definitions)
          save_assistant(reply)
          break unless reply.tool_calls?

          reply.tool_calls.each { |call| run_tool(call) }
          rounds += 1
          next if rounds < MAX_TOOL_ROUNDS

          @conversation.messages.create!(role: :assistant, content: "I've paused after #{MAX_TOOL_ROUNDS} rounds of tools so nothing runs away. Tell me if you'd like me to carry on.")
          break
        end
      rescue StandardError => e
        Rails.logger.error("[Office] reply failed for conversation #{@conversation.id}: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, context: { office_conversation_id: @conversation.id })
        @conversation.messages.create!(role: :assistant, content: FRIENDLY_ERROR,
                                       payload: { "error" => true, "detail" => e.message.truncate(300) })
      ensure
        @conversation.touch_last_message!
        @conversation.thinking!(false)
      end

      # The thread as the provider sees it: the last HISTORY_LIMIT messages,
      # starting at something the founder said, with every tool call answered.
      def history
        records = @conversation.messages.where.not("payload @> ?", { error: true }.to_json)
                               .reorder(id: :desc).limit(HISTORY_LIMIT).to_a.reverse
        records = records.drop_while { |m| !(m.user? || m.card?) }
        answered = records.select(&:tool?).map { |m| m.payload["tool_call_id"] }.to_set

        records.flat_map do |m|
          case m.role
          when "user" then [ { role: :user, text: m.imported? ? imported_text(m) : m.content.to_s } ]
          when "card" then [ { role: :user, text: card_note(m) } ]
          when "tool" then [ tool_entry(m) ]
          when "assistant"
            entry = { role: :assistant, text: m.content.to_s, tool_calls: m.tool_calls, raw: m.payload["raw"] }
            missing = m.tool_calls.reject { |c| answered.include?(c["id"]) }.map do |c|
              { role: :tool, tool_call_id: c["id"], name: c["name"], result: { "error" => "This tool call did not complete." } }
            end
            [ entry, *missing ]
          end
        end
      end

      private

      def system_prompt
        SystemPrompt.build(briefing: OfficeBriefing.current.body, user: @conversation.user)
      end

      def save_assistant(reply)
        @conversation.messages.create!(
          role: :assistant,
          content: reply.text.to_s,
          payload: { "tool_calls" => reply.tool_calls, "raw" => reply.raw, "model" => reply.model, "stop_reason" => reply.stop_reason }.compact
        )
      end

      def run_tool(call)
        outcome = Tools.dispatch(call["name"], call["input"], @context)
        message = @conversation.messages.new(
          role: :tool,
          content: JSON.dump(outcome.result),
          payload: { "tool_call_id" => call["id"], "name" => call["name"], "input" => call["input"],
                     "result" => outcome.result, "card" => outcome.card }.compact
        )
        message.image.attach(outcome.blob) if outcome.blob
        message.save!
        extra = outcome.after_save&.call(message)
        return if extra.blank?

        result = outcome.result.merge(extra)
        message.update_columns(content: JSON.dump(result), payload: message.payload.merge("result" => result))
      end

      # Tool results plus anything the founder has since done on the card
      # (posted it, scheduled it), so the model knows where things stand.
      # Cards made before ids were part of tool results get theirs from the
      # message id, which is what update_breath and flyer_id take.
      def tool_entry(message)
        result = (message.payload["result"] || {}).merge(card_ids(message))
        card = card_now(message)
        result = result.merge("card_now" => card) if card.any?
        { role: :tool, tool_call_id: message.payload["tool_call_id"], name: message.tool_name, result: result }
      end

      def card_note(message)
        ids = card_ids(message)
        details = ids.merge(card_now(message)).map { |k, v| "#{k}: #{v}" }.join(", ")
        "[Office note] #{message.content}#{" (#{details})" if details.present?}"
      end

      def card_ids(message)
        case message.card_kind
        when "breath" then { "breath_id" => message.id }
        when "flyer" then { "flyer_id" => message.id }
        else {}
        end
      end

      def card_now(message)
        card = message.card_data
        now = card.slice("status", "title", "post_id", "scheduled_for", "announcement_id", "error").compact_blank
        now["flyer_id"] = card["image_message_id"] if message.card_kind == "breath" && card["image_message_id"].present?
        now
      end

      def imported_text(message)
        "Notes imported from an earlier conversation, for context. Take them in; there's nothing to do yet " \
          "unless they ask for something.\n\n#{message.content}"
      end
    end
  end
end
