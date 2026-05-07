# frozen_string_literal: true

module Ai
  module Composer
    # Quick "is this gentle?" check for a draft breath. Author-facing — never
    # blocks publish, just offers a nudge if the tone reads as harsh.
    #
    # Returned tones:
    #   "gentle"  — speak life, no nudge needed
    #   "firm"    — strong but ok; no nudge
    #   "harsh"   — could wound a brother; nudge with a reframe
    class GentlenessCheck
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:GENTLENESS]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You are the gentleness coach for Brethreign, a Christian community.
        Your only job is to assess whether a draft post lands in love (Eph 4:15)
        or in a way that could wound a brother or sister unnecessarily.

        Score the *tone*, not the *content*. Sharp truth told in love is fine.
        What you flag:
        - Mocking, contempt, or sarcasm aimed at a person or group.
        - Personal attacks, name-calling, dehumanizing language.
        - Self-righteous shaming or pile-on energy.

        What you do NOT flag:
        - Lament, doubt, raw honesty about pain.
        - Strong rebuke of ideas (not people).
        - Theological disagreement spoken plainly.
        - Confession or recovery testimony.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "tone": "gentle" | "firm" | "harsh",
          "confidence": number 0..1,
          "summary": string (max 200 chars, plain, factual),
          "nudge": string (empty for gentle/firm, otherwise one sentence the user can read and decide),
          "suggestion": string (empty for gentle/firm, otherwise a softer rephrase staying TRUE to their meaning, max 280 chars)
        }
      PROMPT

      Result = Struct.new(:tone, :confidence, :summary, :nudge, :suggestion, keyword_init: true) do
        def gentle?
          tone == "gentle"
        end

        def harsh?
          tone == "harsh"
        end
      end

      def self.call(content:)
        new(content: content).call
      end

      def initialize(content:)
        @content = content.to_s
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)

        Result.new(
          tone: payload.fetch("tone", "gentle"),
          confidence: payload.fetch("confidence", 0.0).to_f,
          summary: payload.fetch("summary", ""),
          nudge: payload.fetch("nudge", ""),
          suggestion: payload.fetch("suggestion", "")
        )
      end

      private

      def user_prompt
        "#{TASK_MARKER}\nDraft to assess:\n---\n#{@content}\n---"
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse gentleness response: #{e.message} — body: #{text}"
      end
    end
  end
end
