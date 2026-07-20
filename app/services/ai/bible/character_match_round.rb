# frozen_string_literal: true

module Ai
  module Bible
    # Character Match round — 5 AI-generated "name the biblical figure"
    # questions in ONE call. Variety comes from three shuffled dials:
    # a large rotating bucket of figures, a clue style, and a random seed.
    # Questions come back ordered easy → hard so every round ramps up.
    class CharacterMatchRound
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:CHARACTER_MATCH]"

      BUCKETS = [
        "the patriarchs and their families (Abraham, Isaac, Jacob, Joseph)",
        "figures of Genesis before Abraham (Adam, Eve, Cain, Enoch, Noah)",
        "Moses, Aaron, Miriam, and the Exodus generation",
        "Joshua, Caleb, and the conquest generation",
        "the judges of Israel (Deborah, Gideon, Jephthah, Samson, Samuel)",
        "women of the Old Testament (Sarah, Rebekah, Rachel, Ruth, Hannah, Abigail)",
        "King Saul, David, and the men and women around David's rise",
        "Solomon and the kings of the divided kingdom",
        "good kings and bad kings of Judah (Hezekiah, Josiah, Manasseh, Ahaz)",
        "Elijah, Elisha, and the prophets of the northern kingdom",
        "the major prophets (Isaiah, Jeremiah, Ezekiel, Daniel)",
        "the minor prophets (Hosea, Amos, Jonah, Micah, Habakkuk, Malachi)",
        "figures of the exile and return (Daniel's friends, Esther, Ezra, Nehemiah, Zerubbabel)",
        "foreign rulers in the Bible (Pharaoh, Nebuchadnezzar, Cyrus, Darius, Caesar)",
        "villains and antagonists (Goliath, Jezebel, Haman, Herod, Judas)",
        "priests and Levites (Aaron, Eli, Zadok, Abiathar, Zechariah the priest)",
        "the twelve disciples of Jesus",
        "women of the New Testament (Mary, Elizabeth, Anna, Martha, Lydia, Priscilla)",
        "the family and forerunners of Jesus (Joseph, John the Baptist, Zechariah, Simeon)",
        "people Jesus met and healed (Zacchaeus, Bartimaeus, Nicodemus, the Samaritan woman)",
        "figures of the early church in Acts (Stephen, Philip, Barnabas, Cornelius, Apollos)",
        "Paul and his companions (Silas, Timothy, Titus, Luke, Onesimus)",
        "lesser-known and obscure figures (Jabez, Ehud, Rizpah, Onesiphorus, Epaphroditus)",
        "messengers and angels, and those who met them (Gabriel, Manoah, Balaam, Cornelius)"
      ].freeze

      CLUE_STYLES = [
        "a short third-person biography",
        "a first-person 'I am...' riddle spoken by the figure",
        "their most famous moment, described without naming them",
        "their family relationships and where they lived",
        "something they said, and the situation they said it in"
      ].freeze

      DIFFICULTY_RANK = { "easy" => 0, "medium" => 1, "hard" => 2 }.freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write "guess the biblical figure" questions for a Christian
        community game. Each question describes a person from the Bible
        WITHOUT naming them; the player picks the right name from 4 options.

        Generate exactly 5 questions from the assigned bucket of figures.

        Rules:
        - Never include the answer's name (or an obvious variant) in the prompt.
        - 4 name choices per question, exactly ONE correct. Wrong choices must
          be plausible — figures from a similar era or role, never absurd.
        - Use 5 DIFFERENT figures — no repeats within the round.
        - Prompt ≤ 240 chars; each choice ≤ 40 chars.
        - Difficulty ramp: questions 1-2 easy (famous figures, famous moments),
          3-4 medium, 5 hard (an obscure figure or a subtle detail).
        - Tag each question with its "difficulty": "easy" | "medium" | "hard".
        - "reference" is the Bible passage where the figure appears (e.g. "Judges 4-5").
        - "explanation" is one warm sentence about who they were.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "questions": [
            {
              "prompt": string,
              "choices": [string, string, string, string],
              "correct_index": 0|1|2|3,
              "difficulty": "easy"|"medium"|"hard",
              "reference": string,
              "explanation": string
            }
          ]
        }
      PROMPT

      Question = Struct.new(:kind, :prompt, :choices, :correct_index, :difficulty,
                            :reference, :explanation, keyword_init: true)

      def self.call(bucket: nil)
        new(bucket: bucket || BUCKETS.sample).call
      end

      def initialize(bucket:)
        @bucket = bucket
        @clue_style = CLUE_STYLES.sample
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)
        questions = Array(payload["questions"]).first(5).filter_map { |q| build_question(q) }
        raise ParseError, "no valid questions" if questions.empty?

        # Guarantee the easy → hard ramp regardless of the order the model
        # returned, then let ties keep their generated order.
        questions.sort_by.with_index { |q, i| [ DIFFICULTY_RANK.fetch(q.difficulty, 1), i ] }
      end

      private

      def build_question(q)
        choices = Array(q["choices"]).map { |c| c.to_s.strip }.first(4)
        correct = q["correct_index"].to_i
        return if choices.size != 4 || choices.any?(&:empty?) ||
                  !(0..3).cover?(correct) || q["prompt"].to_s.strip.empty?

        # Re-shuffle the choices ourselves — models love putting the answer
        # in the same slot, which sharp players learn fast.
        order = (0..3).to_a.shuffle
        difficulty = q["difficulty"].to_s
        difficulty = "medium" unless DIFFICULTY_RANK.key?(difficulty)

        Question.new(
          kind: "character",
          prompt: q["prompt"].to_s.strip,
          choices: order.map { |i| choices[i] },
          correct_index: order.index(correct),
          difficulty: difficulty,
          reference: q["reference"].to_s.strip,
          explanation: q["explanation"].to_s.strip
        )
      end

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Figure bucket: #{@bucket}
          Clue style to lean on: #{@clue_style}
          Generate 5 questions. Seed: #{SecureRandom.hex(4)}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse character-match response: #{e.message} — body: #{text}"
      end
    end
  end
end
