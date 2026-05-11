# frozen_string_literal: true

module Ai
  module Bible
    # Generates a 5-question Bible quiz from the AI. Each question is a
    # multiple-choice with one correct answer index. Mix of: which book,
    # who said it, fill-in-the-blank, character match, event order.
    class QuizGenerator
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_QUIZ]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write Bible trivia questions for a Christian community app.

        Generate exactly 5 multiple-choice questions on the canonical 66-book
        Protestant Bible (KJV phrasing where verses are quoted). Mix the kinds:
        - "which_book": quote a verse, ask which book it's from.
        - "fill_blank": one short verse with a key word blanked out.
        - "character": short description, ask who it is.
        - "event_book": describe a famous event, ask which book it's recorded in.
        - "reference": quote a famous verse, ask the correct chapter:verse.

        Rules:
        - 4 choices per question, exactly ONE correct.
        - Question prompt ≤ 240 chars; each choice ≤ 80 chars.
        - Factually correct — do not invent verses or wrong books.
        - Vary difficulty: 2 easy, 2 medium, 1 hard.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "questions": [
            {
              "kind": "which_book"|"fill_blank"|"character"|"event_book"|"reference",
              "prompt": string,
              "choices": [string, string, string, string],
              "correct_index": 0|1|2|3,
              "reference": string,
              "explanation": string
            }
          ]
        }
      PROMPT

      Question = Struct.new(:kind, :prompt, :choices, :correct_index, :reference, :explanation, keyword_init: true)

      TOPICS = [
        "Genesis and the patriarchs (Abraham, Isaac, Jacob, Joseph)",
        "Exodus and the wilderness wanderings",
        "Judges and Ruth — the chaotic period before the kings",
        "King David — his rise, sins, psalms, family",
        "King Solomon and the divided kingdom",
        "The prophets of Israel and Judah (Isaiah, Jeremiah, Ezekiel)",
        "Minor prophets (Hosea through Malachi)",
        "Daniel and the exile in Babylon",
        "The four Gospels — life and teachings of Jesus",
        "Parables of Jesus",
        "Miracles of Jesus",
        "The Sermon on the Mount",
        "The early church in Acts",
        "Paul's missionary journeys and letters",
        "Hebrews, the general epistles, and Revelation",
        "Bible women (Sarah, Rebekah, Esther, Ruth, Mary, etc.)",
        "Bible numbers, geography, and lesser-known facts"
      ].freeze

      def self.call(topic: nil)
        new(topic: topic || TOPICS.sample).call
      end

      def initialize(topic:)
        @topic = topic
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)
        questions = Array(payload["questions"]).first(5).filter_map do |q|
          choices = Array(q["choices"]).map(&:to_s).first(4)
          correct = q["correct_index"].to_i
          next if choices.size != 4 || !(0..3).cover?(correct) || q["prompt"].to_s.strip.empty?

          Question.new(
            kind: q["kind"].to_s,
            prompt: q["prompt"].to_s.strip,
            choices: choices,
            correct_index: correct,
            reference: q["reference"].to_s.strip,
            explanation: q["explanation"].to_s.strip
          )
        end
        raise ParseError, "no valid questions" if questions.empty?
        questions
      end

      private

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Topic focus for this batch: #{@topic}
          Generate 5 fresh questions, all centered on that topic.
          Make them specific (named people, places, events) rather than
          generic. Seed: #{SecureRandom.hex(4)}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse quiz response: #{e.message} — body: #{text}"
      end
    end
  end
end
