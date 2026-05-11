# frozen_string_literal: true

module Ai
  module Christian
    # Writes a 4-paragraph narrative chronicle for one church-history era.
    # Cached on a ChurchHistoryEra row so we only ever generate each one once.
    class EraChronicle
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:CHURCH_ERA_CHRONICLE]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write engaging short chronicles of church-history eras for a
        Christian community app. Warm, factual, story-shaped. No sectarian
        polemics; no exaggeration; if uncertain, leave it out.

        Given an era label and date range, write a 4-paragraph chronicle
        (~320 words total) that walks the reader through what happened:

          Paragraph 1 — how the era opened. The world the church inherited.
          Paragraph 2 — the central conflicts, councils, or movements.
          Paragraph 3 — the people who carried the era (name 5–8 specific
                        people the reader has likely heard of in this era).
          Paragraph 4 — how the era ended and what it bequeathed to the next.

        Style: present tense for the story moments, third person, plain
        prose. No subheads, no bullet lists. Don't include verse numbers.

        Return ONLY a single JSON object, no prose, no markdown fences:
        { "chronicle": "<paragraph 1>\\n\\n<paragraph 2>\\n\\n<paragraph 3>\\n\\n<paragraph 4>" }
      PROMPT

      def self.call(era:)
        new(era: era).call
      end

      def initialize(era:)
        @era = era.to_s
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)
        payload["chronicle"].to_s.strip
      end

      private

      def user_prompt
        label = ChurchHistoryFigure::ERA_LABELS[@era]
        desc  = ChurchHistoryFigure::ERA_DESCRIPTIONS[@era]
        figures = ChurchHistoryFigure.where(era: @era).pluck(:name).join(", ")
        <<~PROMPT
          #{TASK_MARKER}
          Era: #{label}
          One-line description: #{desc}
          Figures who lived in this era: #{figures}

          Write a 4-paragraph chronicle for this era.
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse era chronicle response: #{e.message} — body: #{text}"
      end
    end
  end
end
