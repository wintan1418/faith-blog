# frozen_string_literal: true

module Ai
  module Bible
    # Formation-themed Bible quiz generator. Each batch draws on a SPECIFIC
    # spiritual theme (salvation, eternal life, brotherly love, charity,
    # etc.) and a SPECIFIC difficulty so the resulting question matches
    # both the theme and the difficulty the player picked. A random
    # epistle/book hint per batch keeps the model from looping on the
    # same handful of famous verses.
    class QuizGenerator
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_QUIZ]"

      # Formation themes we want the quiz to be ABOUT — not "name the king
      # in 2 Kings", but the spiritual realities themselves.
      THEMES = {
        "salvation"      => "the way of salvation — repentance, faith, justification, new birth",
        "eternal_life"   => "eternal life — the believer's hope, inheritance, and assurance",
        "brethren_love"  => "love among the brethren — fellowship, unity, bearing one another",
        "charity"        => "charity / agape — 1 Corinthians 13 and the love commands of Christ",
        "faith"          => "faith — what it is, how it works, examples in the epistles",
        "epistles"       => "the apostolic epistles — doctrine and practice for the church",
        "grace"          => "grace — unmerited favor, sufficient grace, growing in grace",
        "repentance"     => "repentance — turning, godly sorrow, fruits of repentance",
        "holiness"       => "holiness and sanctification — walking in the Spirit, being set apart",
        "prayer"         => "prayer — how to pray, what to pray for, the Lord's prayer",
        "forgiveness"    => "forgiveness — Christ's forgiveness of us and ours of one another",
        "the_cross"      => "the cross — atonement, propitiation, the finished work of Christ",
        "holy_spirit"    => "the Holy Spirit — fruit, gifts, indwelling, walking by the Spirit",
        "hope_of_glory"  => "hope of glory — second coming, resurrection, heaven",
        "obedience"      => "obedience to Christ — fearing God, keeping his commandments",
        "bible_history"  => "Bible history — events, places, and figures across the canon"
      }.freeze

      DIFFICULTIES = %w[easy medium hard].freeze

      # Epistles + Gospels rotation hint so the model spreads across the
      # New Testament instead of recycling famous Romans / 1 Cor / John verses.
      BOOK_HINTS = [
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans", "1 Corinthians", "2 Corinthians", "Galatians",
        "Ephesians", "Philippians", "Colossians",
        "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon",
        "Hebrews", "James", "1 Peter", "2 Peter",
        "1 John", "2 John", "3 John", "Jude", "Revelation"
      ].freeze

      # Where each theme is actually taught. The book hint used to be any NT
      # book at random, so "the cross" could be told to draw from Philemon or
      # 3 John and the model wrote questions about whatever those books say.
      # Now the hint is always a book that speaks to the theme.
      THEME_BOOKS = {
        "salvation"     => [ "John", "Acts", "Romans", "Galatians", "Ephesians", "Titus" ],
        "eternal_life"  => [ "John", "Romans", "1 Corinthians", "2 Corinthians", "1 Peter", "1 John" ],
        "brethren_love" => [ "John", "Acts", "Romans", "Philippians", "1 Thessalonians", "1 Peter", "1 John" ],
        "charity"       => [ "Matthew", "Luke", "John", "1 Corinthians", "1 John", "James" ],
        "faith"         => [ "Mark", "Luke", "Romans", "Galatians", "Hebrews", "James" ],
        "epistles"      => [ "Romans", "1 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
                             "1 Timothy", "Hebrews", "James", "1 Peter", "1 John" ],
        "grace"         => [ "John", "Romans", "2 Corinthians", "Ephesians", "Titus", "Hebrews" ],
        "repentance"    => [ "Matthew", "Luke", "Acts", "2 Corinthians", "2 Peter", "Revelation" ],
        "holiness"      => [ "Romans", "Galatians", "1 Thessalonians", "Hebrews", "1 Peter" ],
        "prayer"        => [ "Matthew", "Luke", "John", "Acts", "Philippians", "James" ],
        "forgiveness"   => [ "Matthew", "Luke", "Acts", "Ephesians", "Colossians", "1 John" ],
        "the_cross"     => [ "Matthew", "Mark", "Luke", "John", "Romans", "1 Corinthians", "Galatians",
                             "Colossians", "Hebrews", "1 Peter" ],
        "holy_spirit"   => [ "John", "Acts", "Romans", "1 Corinthians", "Galatians", "Ephesians" ],
        "hope_of_glory" => [ "John", "1 Corinthians", "Philippians", "1 Thessalonians", "Titus", "Revelation" ],
        "obedience"     => [ "Matthew", "John", "Romans", "Philippians", "Hebrews", "1 John" ],
        "bible_history" => [ "Genesis", "Exodus", "Joshua", "Judges", "1 Samuel", "2 Samuel", "1 Kings",
                             "2 Kings", "Daniel", "Matthew", "Luke", "Acts" ]
      }.freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write Bible quiz questions that form Christians spiritually.

        Every question must be ABOUT the assigned THEME (a spiritual reality)
        and at the assigned DIFFICULTY level. A player who picked the theme
        "the cross" must only see questions about the cross; a verse that
        merely comes from a suggested book is NOT enough. If the suggested
        book has nothing on the theme, use another passage that does. For
        each question, "theme_link" says in a few words how it is about the
        theme; if you can't say, the question is off-theme: replace it.

        Difficulty calibration:
          - easy: an attentive Sunday-school answer; one well-known verse.
          - medium: knows the NT well; can connect 2-3 passages or terms.
          - hard: serious student; lesser-quoted verses, doctrinal nuance.

        Mix the kinds of questions:
          - "which_book": quote a verse, ask which book it's from.
          - "fill_blank": one short verse with a key word blanked.
          - "what_does": quote a verse and ask what it means (multiple choice).
          - "true_phrase": which of these is a verse / phrase Scripture actually uses.
          - "reference": quote a famous verse, ask its chapter:verse.

        Rules:
          - 4 choices per question, exactly ONE correct.
          - Prompt ≤ 240 chars; each choice ≤ 80 chars.
          - Factually accurate; never invent verses or wrong books.
          - Use canonical 66-book Protestant references in KJV-friendly form.
          - The 5 questions in a batch should feel different from each other.

        ACCURACY CONTRACT — this game has shipped wrong answers before, so:
          - Quote scripture EXACTLY as the KJV words it. Never paraphrase a
            quote and present it as the verse.
          - The "explanation" MUST quote the exact KJV wording of the verse
            (with reference) that proves the correct answer.
          - Before returning, RE-CHECK each question: is the choice at
            correct_index the only defensible answer? Could a well-read
            believer argue for any other choice? If yes, rewrite the wrong
            choices until only one answer is correct.
          - If you cannot verify a question word-for-word against the KJV,
            REPLACE it with one you can.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "questions": [
            {
              "kind": "which_book"|"fill_blank"|"what_does"|"true_phrase"|"reference",
              "prompt": string,
              "choices": [string, string, string, string],
              "correct_index": 0|1|2|3,
              "reference": string,
              "explanation": string,
              "theme_link": string
            }
          ]
        }
      PROMPT

      REPLY_TOKENS = 2500

      Question = Struct.new(:kind, :prompt, :choices, :correct_index,
                            :reference, :explanation, :theme, :difficulty,
                            keyword_init: true)

      def self.call(theme: nil, difficulty: nil, book: nil)
        theme      = theme.to_s.presence || THEMES.keys.sample
        difficulty = difficulty.to_s.presence_in(DIFFICULTIES) || DIFFICULTIES.sample
        book       = book.presence || THEME_BOOKS.fetch(theme, BOOK_HINTS).sample
        new(theme: theme, difficulty: difficulty, book: book).call
      end

      def initialize(theme:, difficulty:, book:)
        @theme      = theme
        @difficulty = difficulty
        @book       = book
      end

      def call
        # Five questions with explanations and theme links need far more than the
        # default 600-token reply; at 600 the JSON was cut off mid-question.
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt, max_tokens: REPLY_TOKENS)
        payload = extract_payload(raw)
        questions = Array(payload["questions"]).first(5).filter_map do |q|
          choices = Array(q["choices"]).map(&:to_s).first(4)
          correct = q["correct_index"].to_i
          next if choices.size != 4 || !(0..3).cover?(correct) || q["prompt"].to_s.strip.empty?
          # No stated link to the theme: the model drifted off it, so drop it.
          next if q["theme_link"].to_s.strip.empty?

          # Re-shuffle server-side — models favour certain answer slots and
          # regulars learn the pattern.
          order = (0..3).to_a.shuffle

          question = Question.new(
            kind: q["kind"].to_s,
            prompt: q["prompt"].to_s.strip,
            choices: order.map { |i| choices[i] },
            correct_index: order.index(correct),
            reference: q["reference"].to_s.strip,
            explanation: q["explanation"].to_s.strip,
            theme: @theme,
            difficulty: @difficulty
          )
          checked_answer(question)
        end
        raise ParseError, "no valid questions" if questions.empty?
        questions
      end

      private

      # The marked answer must match the Bible (BibleQuiz::AnswerCheck): a
      # wrongly marked one is corrected when the right choice is clear,
      # otherwise the question is dropped. A fill-in-the-blank we couldn't
      # check against the KJV is dropped too, so players never see a wrong key.
      def checked_answer(question)
        result = BibleQuiz::AnswerCheck.call(kind: question.kind, choices: question.choices,
                                             correct_index: question.correct_index, reference: question.reference)
        case result.status
        when :ok then question
        when :fixed then question.tap { |q| q.correct_index = result.correct_index }
        when :wrong then nil
        else question.kind == "fill_blank" ? nil : question
        end
      end

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          THEME: #{@theme} — #{THEMES[@theme]}
          DIFFICULTY: #{@difficulty}
          SUGGESTED BOOK (only where it speaks to the theme): #{@book}

          Generate 5 questions that are each clearly about #{THEMES[@theme] || @theme},
          at this difficulty. Vary the kinds. Seed: #{SecureRandom.hex(4)}
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
