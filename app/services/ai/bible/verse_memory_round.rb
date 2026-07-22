# frozen_string_literal: true

module Ai
  module Bible
    # Verse Memory — hide the Word in your heart. Each round drills FIVE
    # DIFFERENT verses (the old one-verse-five-blanks design bored players
    # instantly) drawn from a rotating themed set, KJV quoted exactly.
    # Four fill-the-blank questions ramp up to one complete-the-verse
    # finisher. Returns 5 questions in the shape quiz_controller expects.
    class VerseMemoryRound
      class Error < StandardError; end

      TASK_MARKER = "[TASK:VERSE_MEMORY]"

      # Rotating verse sets so consecutive rounds feel different. The lists
      # are suggestions — the model may swap in equally-known verses on the
      # same theme.
      VERSE_SETS = [
        "God's love — John 3:16, Romans 5:8, 1 John 4:19, Ephesians 2:4-5, Romans 8:38-39",
        "faith — Hebrews 11:1, Romans 10:17, 2 Corinthians 5:7, Mark 11:24, Ephesians 2:8-9",
        "courage and strength — Joshua 1:9, Isaiah 41:10, Philippians 4:13, Psalm 27:1, 2 Timothy 1:7",
        "beloved Psalms — Psalm 23:1, Psalm 46:10, Psalm 119:105, Psalm 34:8, Psalm 91:1-2",
        "promises of God — Jeremiah 29:11, Romans 8:28, Philippians 4:19, Isaiah 40:31, Matthew 6:33",
        "words of Jesus — Matthew 11:28, John 14:6, John 10:10, Matthew 5:16, John 8:32",
        "wisdom from Proverbs — Proverbs 3:5-6, Proverbs 18:10, Proverbs 16:9, Proverbs 4:23, Proverbs 22:6",
        "comfort in trials — 2 Corinthians 12:9, 1 Peter 5:7, Psalm 34:18, James 1:2-3, Romans 12:12",
        "prayer — Philippians 4:6-7, 1 Thessalonians 5:16-18, Matthew 7:7, James 5:16, 1 John 5:14",
        "new life in Christ — 2 Corinthians 5:17, Galatians 2:20, Colossians 3:1-2, Romans 6:4, Ephesians 4:22-24",
        "hope and heaven — John 14:2-3, Revelation 21:4, 1 Corinthians 2:9, Titus 2:13, 1 Peter 1:3",
        "holiness and obedience — Romans 12:1-2, 1 Peter 1:15-16, John 14:15, Micah 6:8, Galatians 5:22-23"
      ].freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You build verse-memorization drills from the KJV. You will be given
        a themed set of verses. Use FIVE DIFFERENT verses from that theme —
        never two questions on the same verse.

        Question formats:
          - Questions 1-4: quote the verse EXACTLY as the KJV words it, with
            ONE key word replaced by "____". 4 choices: the correct word +
            3 plausible distractors (same part of speech, similar weight).
          - Question 5 (the finisher): quote the verse's opening and blank
            the ENDING — "…that whosoever believeth in him ____". 4 choices
            are short phrases; only one is the true KJV ending.

        Rules:
          - Quote the KJV word-for-word. Never paraphrase.
          - Each question carries its OWN "reference".
          - Order easy → hard (most famous verse first, subtlest last).
          - Each prompt ≤ 240 chars; explanation gives the full phrase back
            with its reference.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "questions": [
            {
              "prompt": "Trust in the LORD with all thine heart; and lean not unto thine own ____;",
              "choices": ["understanding", "strength", "wisdom", "knowledge"],
              "correct_index": 0,
              "reference": "Proverbs 3:5",
              "explanation": "…lean not unto thine own understanding (Proverbs 3:5)."
            }
          ]
        }
      PROMPT

      def self.call
        new.call
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)

        difficulties = %w[easy easy medium medium hard]
        questions = Array(payload["questions"]).first(5).each_with_index.filter_map do |q, i|
          choices = Array(q["choices"]).map(&:to_s).first(4)
          correct = q["correct_index"].to_i
          next if choices.size != 4 || !(0..3).cover?(correct) || q["prompt"].to_s.strip.empty?

          # Re-shuffle so the correct slot can't be learned.
          order = (0..3).to_a.shuffle

          {
            kind: "verse_memory",
            prompt: q["prompt"].to_s.strip,
            choices: order.map { |j| choices[j] },
            correct_index: order.index(correct),
            reference: q["reference"].to_s.strip,
            explanation: q["explanation"].to_s.strip,
            theme: "verse_memory",
            difficulty: difficulties[i] || "medium"
          }
        end
        raise Error, "no valid questions" if questions.empty?
        questions
      end

      private

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Theme set for this round: #{VERSE_SETS.sample}
          Five different verses, formats as instructed.
          Generate one round. Seed: #{SecureRandom.hex(4)}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Error, "could not parse verse-memory response: #{e.message} — body: #{text}"
      end
    end
  end
end
