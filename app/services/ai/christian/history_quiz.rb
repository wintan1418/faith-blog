# frozen_string_literal: true

module Ai
  module Christian
    # Christian church-history quiz — AI-generated, multiple choice.
    # 17 rotating topic buckets so consecutive plays don't repeat.
    class HistoryQuiz
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:CHURCH_HISTORY_QUIZ]"

      TOPICS = [
        "the early church and the apostolic fathers (Ignatius, Polycarp, Clement)",
        "Augustine of Hippo and the Latin fathers",
        "Athanasius, Arianism, and the Council of Nicaea (325 AD)",
        "the desert fathers and early monasticism",
        "missions to Britain, Ireland, and the Celtic church",
        "the great schism of 1054 — East and West",
        "medieval mystics and reformers (Bernard of Clairvaux, John Hus, Wycliffe)",
        "the Protestant Reformation (Luther, Zwingli, Calvin)",
        "the Anabaptists and the Radical Reformation",
        "the English Reformation (Cranmer, Tyndale, the King James Bible)",
        "the Wesleys, the Methodists, and the Great Awakening",
        "modern missionaries (Hudson Taylor, William Carey, David Livingstone)",
        "African missions and indigenous Christianity (Mary Slessor, Samuel Crowther)",
        "the Pentecostal awakening and global revivals",
        "famous hymn writers (Charles Wesley, Isaac Watts, Fanny Crosby)",
        "Christian creeds and councils (Apostles', Nicene, Chalcedon)",
        "20th-century witnesses (Bonhoeffer, C.S. Lewis, Corrie ten Boom)"
      ].freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write trivia questions about Christian church history for a
        Christian community app. Stay factual; avoid sectarian polemics.

        Generate exactly 5 multiple-choice questions on the assigned topic.

        Rules:
        - 4 choices per question, exactly ONE correct.
        - Prompt ≤ 240 chars; each choice ≤ 80 chars.
        - Be specific (named people, places, dates, events) — not generic.
        - Mix difficulty: 2 easy, 2 medium, 1 hard.
        - Don't reference verse numbers (this is HISTORY, not Bible).

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "questions": [
            {
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
            kind: "history",
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
          Topic focus: #{@topic}
          Generate 5 questions centered on this topic. Seed: #{SecureRandom.hex(4)}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse history-quiz response: #{e.message} — body: #{text}"
      end
    end
  end
end
