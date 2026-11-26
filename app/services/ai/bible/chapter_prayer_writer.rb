# frozen_string_literal: true

module Ai
  module Bible
    # Writes the prayer burden a member prays after reading one chapter
    # ("Read your Bible, pray every day"). Called only by ChapterPrayerJob; the
    # result is stored in chapter_prayers (version ChapterPrayer::VERSION).
    #
    # The model gets the whole chapter (KJV, plus the World English Bible when
    # we hold it), verse by verse, and works from the text outward: the
    # chapter's 2-4 key themes and 1-3 weightiest verses first, then "today's
    # burden" (what this chapter calls us to pray about), 3-5 prayer points
    # each tied to a verse of this chapter, and a short closing prayer.
    #
    # Guardrails, checked here before anything is stored, and the reply is
    # sent back for another try (up to MAX_ATTEMPTS) when one fails: every
    # point cites a verse that exists in this chapter; no words put in God's
    # mouth; no prosperity promises; no thee/thou; no generic filler ("thank
    # you for this chapter"); first person, ends with Amen; nothing the local
    # offensive-language check would block.
    class ChapterPrayerWriter
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_CHAPTER_PRAYER]"
      MAX_TOKENS = 1_200
      TIMEOUT = 60
      MAX_ATTEMPTS = 3
      # Characters of chapter text sent per translation. Psalm 119, the longest
      # chapter, is about 25k in the KJV, so nothing real is ever cut.
      TEXT_LIMIT = 30_000
      TRANSLATIONS = { "kjv" => "King James Version", "web" => "World English Bible" }.freeze
      POINT_KINDS = %w[praise thanksgiving confession lament trust intercession application].freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You help members of a non-denominational Christian community app pray
        after they have read one chapter of the Bible. You are given the whole
        chapter, verse by verse (King James Version, and the World English
        Bible where available). Everything you write must come out of THIS
        chapter's text.

        Work in this order:
        1. "themes": read the whole chapter and name its 2 to 4 key themes in a
           few words each, in the chapter's own terms (who God is here, what he
           does, what he asks, who is in the story, what goes wrong, what is
           promised).
        2. "key_verses": the 1 to 3 verses that carry the chapter's weight.
        3. "burden": "Today's burden", 1 or 2 sentences (20 to 60 words) saying
           what this chapter calls us to pray about. Someone who has just read
           the chapter should recognise it at once; it should not fit any other
           chapter.
        4. "points": 3 to 5 prayer points. Each is ONE line of 8 to 30 words that
           starts with a verb (Praise, Thank, Confess, Ask, Pray for, Commit,
           Bring...) and is tied to ONE verse of this chapter, given in
           "reference" ("John 1:14", or a short range like "John 1:12-13"). Do
           not repeat the reference inside the text. Give each a "kind":
           - "praise": who God is or what he has done, as this chapter shows it
           - "confession": repentance where the chapter convicts (only if it does)
           - "intercession": for others, the church, the nation or the world, as
             the chapter warrants
           - "application": a concrete step of trust or obedience for today
           - also allowed when the chapter calls for them: "thanksgiving",
             "lament", "trust"
           Use at least three different kinds, in a natural order (usually
           praise first, application last).
        5. "prayer": a closing prayer of 4 to 6 sentences (70 to 170 words) that
           weaves the points together, in the first person singular ("I", "me",
           "my"), addressed to God ("Lord", "Father", "God" or "Jesus"), and
           ending with "Amen."

        Rules for everything you write:
        - Plain modern English. Never "thee", "thou", "thy", "thine", "hath" or
          "-eth" words, even when echoing the KJV.
        - Never speak FOR God: no "God says", "God is telling you", "my child",
          prophecies or promises in God's voice. Say only what the chapter
          itself says about God.
        - No prosperity teaching: no wealth, success, breakthrough, favour or
          increase; no "claim", "declare", "decree"; no guaranteed healing or
          outcomes.
        - Theologically careful and non-denominational: historic Christian
          faith, no sectarian positions (baptism, end-times schemes, gifts,
          church government), no party politics, no church jargon.
        - No generic filler. Never "thank you for this chapter", "thank you for
          your Word today", "thank you for John 1", "help me apply this
          passage". Every line must carry something only this chapter says:
          its people, events, images, commands or promises.
        - Hard chapters (judgment, war, law, genealogies, lament): pray honestly
          about what they show (God's holiness, justice, patience, faithfulness
          across generations). Don't invent comfort the chapter doesn't give,
          and don't turn commands given to Israel into direct commands for
          today without care.

        Return ONLY one JSON object, no markdown:
        {
          "themes": ["...", "..."],
          "key_verses": ["Book C:V"],
          "burden": "...",
          "points": [{ "kind": "praise", "text": "...", "reference": "Book C:V" }],
          "prayer": "... Amen."
        }
      PROMPT

      # Words that would put a voice or a promise where it doesn't belong.
      BLOCKED = [
        /\b(god|the lord|jesus|he|the spirit) (says|is saying|is telling you|tells you|declares|is declaring)\b/i,
        /\bthus (says|saith)\b/i,
        /\bmy (child|son|daughter),/i,
        /\b(bless|give|grant|make) (me|us)( with)? (wealth|riches|money|success|prosperity)\b/i,
        /\b(prosperity|breakthrough|millionaire|abundance of wealth)\b/i,
        /\bfinancial (blessing|increase|miracle)\b/i,
        /\b(i|we) (claim|declare|decree|command)\b/i,
        /\bname it\b/i,
        /\b(thee|thou|thy|thine|hath|doth)\b/i
      ].freeze

      # "Thank you for this chapter", "thank you for John 1": the shallow
      # prayers this writer exists to replace.
      FILLER = [
        /\bthank(s| you)?( god| lord| father)? for (this|today'?s|the|your) (chapter|passage|reading|text)\b/i,
        /\bthank(s| you)?( god| lord| father)? for (your|the) word (today|this morning|tonight)\b/i,
        /\bfor speaking (to me )?through (this|today'?s) (chapter|passage|reading)\b/i,
        /\bhelp me (to )?apply (this|the|today'?s) (chapter|passage|reading)\b/i,
        /\bwhat i (have )?read today\b/i
      ].freeze

      def self.call(reference:, texts:)
        new(reference: reference, texts: texts).call
      end

      # texts: { "kjv" => [[1, "In the beginning…"], …], "web" => […] }
      def initialize(reference:, texts:)
        @reference = reference.chapter_reference
        @texts = texts.to_h.slice(*TRANSLATIONS.keys).select { |_, verses| Array(verses).any? }
        raise ArgumentError, "no chapter text" if @texts.empty?
      end

      # => { themes:, key_verses:, burden:, points: [{ text:, reference:, kind: }], prayer:, model: }
      # Raises ParseError when every attempt broke a guardrail.
      def call
        problem = nil
        MAX_ATTEMPTS.times do
          raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt(problem), max_tokens: MAX_TOKENS, timeout: TIMEOUT)
          begin
            result = build(extract_payload(raw))
            result[:model] = raw["model"].to_s.presence
            validate!(result)
            return result
          rescue ParseError => e
            problem = e.message
          end
        end
        raise ParseError, problem
      end

      def user_prompt(problem = nil)
        parts = [ TASK_MARKER, "Chapter: #{@reference.plain} (#{verse_numbers.size} verses)", "" ]
        @texts.each do |code, verses|
          parts << "#{TRANSLATIONS[code]}:"
          parts << verses.map { |number, text| "#{number} #{text}" }.join("\n").truncate(TEXT_LIMIT, separator: "\n")
          parts << ""
        end
        if problem
          parts << "Your previous answer was rejected: #{problem}."
          parts << "Write the whole JSON again for #{@reference.plain}, fixing that and keeping every rule."
        end
        parts.join("\n")
      end

      private

      def verse_numbers
        @verse_numbers ||= @texts.values.flat_map { |verses| verses.map { |number, _| number.to_i } }.to_set
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        payload = JSON.parse(text)
        raise ParseError, "the reply is not a JSON object" unless payload.is_a?(Hash)

        payload
      rescue JSON::ParserError => e
        raise ParseError, "could not parse the JSON (#{e.message.truncate(80)})"
      end

      def build(payload)
        {
          themes: Array(payload["themes"]).map { |t| t.to_s.squish }.compact_blank.uniq,
          key_verses: Array(payload["key_verses"]).map { |v| verse!(v, "key verse") },
          burden: payload["burden"].to_s.squish,
          points: Array(payload["points"]).map { |point| build_point(point) },
          prayer: payload["prayer"].to_s.squish
        }
      end

      def build_point(point)
        raise ParseError, "each prayer point must be an object with text and reference" unless point.is_a?(Hash)

        reference = verse!(point["reference"], "prayer point")
        text = point["text"].to_s.squish
        # "(John 1:14)" or "— John 1:14" at the end: the reference is shown on its own.
        text = text.sub(/\s*[(\[–—-]*\s*#{Regexp.escape(@reference.book.ref_name)}\s+\d+:\d+(?:[-–]\d+)?\s*[)\]]?\.?\z/i, "").strip
        text = "#{text}." unless text.match?(/[.!?]\z/)
        { text: text, reference: reference, kind: point["kind"].to_s.downcase.strip }
      end

      # A verse (or short range) of THIS chapter that really exists, in display form.
      def verse!(text, what)
        ref = Scripture::Reference.parse(text.to_s.strip)
        unless ref && !ref.chapter? && ref.book == @reference.book && ref.chapter == @reference.chapter
          raise ParseError, "#{what} reference #{text.to_s.inspect} is not a verse of #{@reference.plain}"
        end
        unless ref.verses.all? { |n| verse_numbers.include?(n) } && ref.verse_count <= 6
          raise ParseError, "#{what} reference #{ref} is not a verse in the text of #{@reference.plain}"
        end

        ref.to_s
      end

      def validate!(result)
        themes, key_verses, burden, points, prayer = result.values_at(:themes, :key_verses, :burden, :points, :prayer)
        raise ParseError, "give 2 to 4 themes (got #{themes.size})" unless themes.size.between?(2, 4)
        raise ParseError, "each theme should be a few words" if themes.any? { |t| t.length > 90 }
        raise ParseError, "give 1 to 3 key verses (got #{key_verses.size})" unless key_verses.uniq.size.between?(1, 3)

        raise ParseError, "the burden should be 1 or 2 sentences of 20 to 60 words" unless sentences(burden).between?(1, 2) && words(burden).between?(12, 75)

        raise ParseError, "give 3 to 5 prayer points (got #{points.size})" unless points.size.between?(3, 5)
        points.each do |point|
          raise ParseError, "prayer point kind #{point[:kind].inspect} is not one of #{POINT_KINDS.join(', ')}" unless POINT_KINDS.include?(point[:kind])
          raise ParseError, "each prayer point should be one line of 8 to 30 words" unless words(point[:text]).between?(6, 38)
        end
        raise ParseError, "use at least three different kinds of prayer point" if points.map { |p| p[:kind] }.uniq.size < 3
        raise ParseError, "two prayer points say the same thing" if points.map { |p| p[:text].downcase }.uniq.size < points.size

        raise ParseError, "the closing prayer should be 4 to 6 sentences" unless sentences(prayer).between?(4, 7) # "Amen." may stand alone
        raise ParseError, "the closing prayer should be 70 to 170 words" unless words(prayer).between?(55, 200)
        raise ParseError, "the closing prayer must be in the first person (I, me, my)" unless prayer.match?(/\b(I|me|my)\b/)
        raise ParseError, "the closing prayer must end with Amen." unless prayer.match?(/\bAmen\.?\z/i)

        everything = [ burden, prayer, *points.map { |p| p[:text] }, *themes ]
        everything.each do |text|
          if (hit = BLOCKED.find { |pattern| text.match?(pattern) })
            raise ParseError, "blocked phrasing (#{hit.source}) in #{text.truncate(60).inspect}"
          end
          if (hit = (FILLER + [ chapter_thanks ]).find { |pattern| text.match?(pattern) })
            raise ParseError, "generic filler (#{hit.source}) in #{text.truncate(60).inspect}; say what the chapter says instead"
          end
          raise ParseError, "offensive language" if CleanLanguage.offensive?(text)
        end
      end

      # "Thank you for John 1" / "for Psalm 23 today".
      def chapter_thanks
        /\bthank(s| you)?( god| lord| father)? for #{Regexp.escape(@reference.book.ref_name)}s? #{@reference.chapter}\b(?!:)/i
      end

      def sentences(text) = text.split(/(?<=[.!?])\s+/).count { |s| s.match?(/[[:alpha:]]/) }
      def words(text) = text.split.size
    end
  end
end
