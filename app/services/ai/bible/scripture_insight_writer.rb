# frozen_string_literal: true

module Ai
  module Bible
    # Writes the explanation, context and reflection questions for one
    # scripture page. Called only by ScriptureInsightJob (never on a page
    # view); the result is stored in scripture_insights.
    class ScriptureInsightWriter
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_PAGE_INSIGHT]"
      MAX_TOKENS = 1_100
      TIMEOUT = 45
      PASSAGE_LIMIT = 2_400 # characters of a long chapter sent as grounding

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write short study notes for a public Bible reference page, read by
        anyone curious: believers, sceptics, students, people who just searched
        a verse. Be faithful to the text, plain-spoken and warm. Non-denominational:
        no church jargon, no sermonising, no altar calls, no sectarian positions.
        Where Christians read a passage differently, say so in one fair sentence.
        Where authorship or dating is uncertain, say "traditionally attributed to"
        or give the range scholars suggest. Never invent facts, quotes or numbers.
        Quote scripture only in King James Version wording.

        Given a reference and its text, return ONLY one JSON object (no markdown):
        {
          "summary": "One sentence (max 150 characters) saying what the passage is about, for a search result. No quotation marks.",
          "explanation": "What it means, in plain English: 2 short paragraphs (110-170 words total) separated by \\n\\n.",
          "context": "Who wrote it, to whom, when and why, and where it sits in the book or chapter: 1-2 short paragraphs (80-140 words).",
          "questions": ["Three open reflection questions a thoughtful reader could sit with, one sentence each."]
        }
      PROMPT

      def self.call(reference:, passage_text:)
        new(reference: reference, passage_text: passage_text).call
      end

      def initialize(reference:, passage_text:)
        @reference = reference
        @passage_text = passage_text.to_s
      end

      # => { summary:, explanation:, context:, questions: [..], model: }
      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt, max_tokens: MAX_TOKENS, timeout: TIMEOUT)
        payload = extract_payload(raw)
        result = {
          summary: payload["summary"].to_s.strip.delete("\"“”").truncate(300, separator: " "),
          explanation: payload["explanation"].to_s.strip,
          context: payload["context"].to_s.strip,
          questions: Array(payload["questions"]).map { |q| q.to_s.strip }.compact_blank.first(3),
          model: raw["model"].to_s.presence
        }
        validate!(result)
        result
      end

      private

      def user_prompt
        kind = @reference.chapter? ? "the whole chapter" : "this passage"
        <<~PROMPT
          #{TASK_MARKER}
          Reference: #{@reference.plain} (#{kind})
          Text (KJV): #{@passage_text.truncate(PASSAGE_LIMIT, separator: " ")}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        payload = JSON.parse(text)
        raise ParseError, "insight reply is not an object" unless payload.is_a?(Hash)

        payload
      rescue JSON::ParserError => e
        raise ParseError, "could not parse insight: #{e.message}"
      end

      def validate!(result)
        raise ParseError, "explanation too short" if result[:explanation].length < 200
        raise ParseError, "context too short" if result[:context].length < 120
        raise ParseError, "expected 2-3 questions" if result[:questions].size < 2
      end
    end
  end
end
