# frozen_string_literal: true

module Ai
  module Composer
    # Suggests up to 3 scripture references that match the heart of a draft
    # breath. Author-facing — they choose whether to fold any in.
    class ScriptureSuggester
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:SCRIPTURE]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You suggest scripture for posts on Brethreign, a Christian community.

        Read the draft, discern the spiritual theme (lament, gratitude, doubt,
        repentance, fear, hope, etc.), and propose UP TO 3 short Bible
        references that meet the writer where they are.

        Rules:
        - Use canonical 66-book Protestant references; KJV/ESV/NIV-style
          format like "Romans 8:28" or "Psalm 34:18" or "John 11:35".
        - Prefer specific verses or 2-3 verse spans, not full chapters.
        - Each reason is ONE plain sentence, max 140 chars, no preachiness.
        - If the draft is too short or unclear to discern a theme, return an
          empty list — never reach.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "verses": [
            { "reference": string, "reason": string }
          ]
        }
      PROMPT

      Verse = Struct.new(:reference, :reason, keyword_init: true)

      Result = Struct.new(:verses, keyword_init: true) do
        def empty?
          verses.empty?
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

        verses = Array(payload["verses"]).first(3).map do |v|
          ref = v["reference"].to_s.strip
          next if ref.blank?

          Verse.new(reference: ref, reason: v["reason"].to_s.strip)
        end.compact

        Result.new(verses: verses)
      end

      private

      def user_prompt
        "#{TASK_MARKER}\nDraft:\n---\n#{@content}\n---"
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse scripture response: #{e.message} — body: #{text}"
      end
    end
  end
end
