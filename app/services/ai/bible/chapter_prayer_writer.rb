# frozen_string_literal: true

module Ai
  module Bible
    # Writes the short prayer a member prays after reading one chapter
    # ("Read your Bible, pray every day"). Called only by ChapterPrayerJob;
    # the result is stored in chapter_prayers.
    #
    # Guardrails, checked here before anything is stored: 3-5 sentences in
    # the first person, rooted in verses that really are in this chapter, no
    # words put in God's mouth, no prosperity-gospel promises, nothing the
    # local offensive-language check would block.
    class ChapterPrayerWriter
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_CHAPTER_PRAYER]"
      MAX_TOKENS = 500
      TIMEOUT = 30
      PASSAGE_LIMIT = 3_200 # characters of a long chapter sent as grounding

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write one short prayer for a person who has just read a chapter of
        the Bible, for a non-denominational Christian community app. They will
        pray it as their own words.

        Rules:
        - 3 to 5 sentences, 60 to 130 words, plain modern English (no thee/thou).
        - First person singular ("I", "me", "my"), addressed to God ("Lord", "Father", "Jesus" or "God").
        - Rooted in what this chapter actually says: name its people, images or
          teaching. Do not drift into generic devotion.
        - Ask, thank, confess, trust. Never speak FOR God: no "God says",
          "I am telling you, my child", promises or prophecies in God's voice.
        - No prosperity promises (wealth, success, breakthrough, favour, "claim",
          "declare", "decree"). No guarantees of healing or outcomes.
        - Theologically careful and non-denominational: no sectarian positions,
          no politics, no church jargon.
        - End with "Amen."

        Return ONLY one JSON object (no markdown):
        {
          "prayer": "The prayer.",
          "verses": ["1 to 3 key verse references from THIS chapter that the prayer draws on, like \\"John 3:16\\""]
        }
      PROMPT

      # Words that would put a promise or a voice where it doesn't belong.
      BLOCKED = [
        /\b(god|the lord|jesus|he) (says|is saying|tells you|declares)\b/i,
        /\bthus (says|saith)\b/i,
        /\bmy (child|son|daughter),/i,
        /\b(bless|give|grant|make) (me|us)( with)? (wealth|riches|money|success|prosperity)\b/i,
        /\b(prosperity|breakthrough|millionaire)\b/i,
        /\bfinancial (blessing|increase|miracle)\b/i,
        /\b(i|we) (claim|declare|decree|command)\b/i,
        /\bname it\b/i,
        /\bthee\b|\bthou\b|\bthy\b/i
      ].freeze

      def self.call(reference:, passage_text:)
        new(reference: reference, passage_text: passage_text).call
      end

      def initialize(reference:, passage_text:)
        @reference = reference.chapter_reference
        @passage_text = passage_text.to_s
      end

      # => { prayer:, verses: ["John 3:16"], model: }
      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt, max_tokens: MAX_TOKENS, timeout: TIMEOUT)
        payload = extract_payload(raw)
        result = {
          prayer: payload["prayer"].to_s.squish,
          verses: verses_from(payload["verses"]),
          model: raw["model"].to_s.presence
        }
        validate!(result)
        result
      end

      private

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Chapter: #{@reference.plain}
          Text (KJV): #{@passage_text.truncate(PASSAGE_LIMIT, separator: " ")}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        payload = JSON.parse(text)
        raise ParseError, "prayer reply is not an object" unless payload.is_a?(Hash)

        payload
      rescue JSON::ParserError => e
        raise ParseError, "could not parse prayer: #{e.message}"
      end

      # Only verses that exist in this very chapter, in display form, at most three.
      def verses_from(list)
        Array(list).filter_map do |text|
          ref = Scripture::Reference.parse(text.to_s)
          next unless ref && !ref.chapter? && ref.book == @reference.book && ref.chapter == @reference.chapter

          ref.to_s
        end.uniq.first(3)
      end

      def validate!(result)
        prayer = result[:prayer]
        sentences = prayer.split(/(?<=[.!?])\s+/).count { |s| s.match?(/[[:alpha:]]/) }
        raise ParseError, "expected 3-5 sentences, got #{sentences}" unless sentences.between?(3, 6) # "Amen." may stand alone
        raise ParseError, "prayer length #{prayer.length}" unless prayer.length.between?(200, 900)
        raise ParseError, "not first person" unless prayer.match?(/\b(I|me|my)\b/)
        raise ParseError, "missing Amen" unless prayer.match?(/\bAmen\.?\z/i)
        raise ParseError, "no verse from this chapter" if result[:verses].empty?
        if (hit = BLOCKED.find { |pattern| prayer.match?(pattern) })
          raise ParseError, "blocked phrasing (#{hit.source})"
        end
        raise ParseError, "offensive language" if CleanLanguage.offensive?(prayer)
      end
    end
  end
end
