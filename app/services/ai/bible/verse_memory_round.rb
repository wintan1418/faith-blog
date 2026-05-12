# frozen_string_literal: true

module Ai
  module Bible
    # Verse Memory: pick a famous verse, blank out 5 key words, generate
    # 4 plausible answer choices per blank. Returns an array of 5 questions
    # in the shape the gamy quiz_controller already expects, so the play
    # screen Just Works.
    class VerseMemoryRound
      class Error < StandardError; end

      TASK_MARKER = "[TASK:VERSE_MEMORY]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You build verse-memorization drills. Pick ONE well-known KJV verse
        (or short two-verse span) on a Christian formation theme — salvation,
        faith, love, grace, hope, holiness, prayer, eternal life. Choose a
        widely-quoted verse from the New Testament (e.g. John 3:16,
        Romans 8:28, 1 Cor 13:4, Eph 2:8-9, Phil 4:13, Heb 11:1).

        Then identify exactly 5 KEY words from that verse and build a
        multiple-choice question for each:
          - prompt: the verse with the key word replaced by "____"
          - 4 choices: the correct word + 3 plausible distractors
            (similar length / part of speech; do not include obvious
            wrong choices)

        Rules:
          - All 5 questions reference the SAME verse.
          - Reference + translation tag must be the same on every question.
          - Each prompt ≤ 240 chars.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "reference": "John 3:16",
          "translation": "KJV",
          "verse_text": "For God so loved the world, …",
          "questions": [
            {
              "prompt": "For God so ____ the world, that he gave his only begotten Son…",
              "choices": ["loved", "made", "saw", "knew"],
              "correct_index": 0,
              "explanation": "John 3:16 — the well-known verse on God's love."
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
        ref   = payload["reference"].to_s
        trans = payload["translation"].presence || "KJV"

        questions = Array(payload["questions"]).first(5).filter_map do |q|
          choices = Array(q["choices"]).map(&:to_s).first(4)
          correct = q["correct_index"].to_i
          next if choices.size != 4 || !(0..3).cover?(correct) || q["prompt"].to_s.strip.empty?

          {
            kind: "verse_memory",
            prompt: q["prompt"].to_s.strip,
            choices: choices,
            correct_index: correct,
            reference: ref,
            explanation: q["explanation"].to_s.strip,
            theme: "verse_memory",
            difficulty: "medium"
          }
        end
        raise Error, "no valid questions" if questions.empty?
        questions
      end

      private

      def user_prompt
        "#{TASK_MARKER}\nGenerate one round. Seed: #{SecureRandom.hex(4)}"
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
