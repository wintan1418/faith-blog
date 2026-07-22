# frozen_string_literal: true

module Ai
  module Bible
    # 4 Pics 1 Word — Bible edition. Each "puzzle" is a row of 4 emoji that
    # together hint at a Bible story, character, or concept. User picks the
    # answer from 4 choices. Returns 5 puzzles per round in the shape the
    # gamy quiz_controller already expects.
    class PicWordRound
      class Error < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_PIC_WORD]"

      # Rotating category buckets — one per round — so consecutive rounds
      # pull from different corners of scripture instead of recycling the
      # same famous handful (players called the old rounds monotonous).
      CATEGORIES = [
        "miracles of Jesus (healings, feedings, storms, resurrections)",
        "parables of Jesus (sower, prodigal, talents, good Samaritan...)",
        "Old Testament heroes and their defining moments",
        "women of the Bible (Ruth, Esther, Deborah, Mary, Lydia...)",
        "kings, thrones, and royal drama (Saul, David, Solomon, Ahab...)",
        "prophets and their strange assignments (Elijah, Ezekiel, Hosea...)",
        "journeys and escapes (Exodus, Paul's voyages, flight to Egypt...)",
        "creation, patriarchs, and Genesis scenes",
        "the early church in Acts (Pentecost, prison breaks, conversions)",
        "objects and symbols of scripture (ark, altar, lampstand, jars...)",
        "battles and impossible victories (Jericho, Gideon, Jehoshaphat...)",
        "angels, dreams, and visions (Jacob's ladder, Gabriel, Revelation)"
      ].freeze

      TWISTS = [
        "make one puzzle a play on a specific verse rather than a story",
        "include one deliberately tricky pair of similar stories as answer/decoy",
        "include one lesser-known story a casual reader might miss",
        "include one puzzle about a place rather than a person",
        "include one puzzle where the emoji tell the story in sequence"
      ].freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You design '4 Pics 1 Word' puzzles, Bible edition. For each puzzle:
          - Pick a well-known Bible story, character, miracle, parable,
            or doctrinal concept.
          - Compose a clue of 4 EMOJI that together visually hint at the
            answer. Use 4 distinct emoji (no repeats).
          - Provide the correct answer + 3 plausible wrong choices.

        Example shape:
          "🦁🕳️🙏👑"  → Daniel in the lions' den
          "🚢🌊🐟⛵"  → Jonah and the great fish
          "🍞🐟🐟🙌"  → Feeding of the 5000
          "✝️🏔️🌑3️⃣"  → The crucifixion / Calvary

        Rules:
          - Exactly 5 puzzles per round.
          - All 5 answers must be DIFFERENT stories / concepts.
          - Mix easy (Jonah, Noah) with medium (Mary anoints, road to Emmaus).
          - Each answer ≤ 60 chars; each wrong choice ≤ 60 chars.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "puzzles": [
            {
              "emoji": "🦁🕳️🙏👑",
              "answer": "Daniel in the lions' den",
              "wrong": ["David vs Goliath", "Joseph in prison", "Paul shipwrecked"],
              "reference": "Daniel 6",
              "explanation": "Daniel was thrown into the lions' den for praying to God."
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

        puzzles = Array(payload["puzzles"]).first(5).filter_map do |p|
          emoji  = p["emoji"].to_s.strip
          answer = p["answer"].to_s.strip
          wrongs = Array(p["wrong"]).map(&:to_s).reject(&:blank?).first(3)
          next if emoji.empty? || answer.empty? || wrongs.size < 3

          choices = (wrongs + [ answer ]).shuffle
          correct = choices.index(answer) || 0

          {
            kind: "pic_word",
            prompt: emoji,
            choices: choices,
            correct_index: correct,
            reference: p["reference"].to_s.strip,
            explanation: p["explanation"].to_s.strip,
            theme: "pic_word",
            difficulty: "medium"
          }
        end
        raise Error, "no valid puzzles" if puzzles.empty?
        puzzles
      end

      private

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Category for this round: #{CATEGORIES.sample}
          Twist: #{TWISTS.sample}
          All 5 puzzles must come from this category, all different stories.
          Difficulty mix: 2 easy, 2 medium, 1 genuinely tricky.
          Generate one round of 5 puzzles. Seed: #{SecureRandom.hex(4)}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Error, "could not parse pic-word response: #{e.message} — body: #{text}"
      end
    end
  end
end
