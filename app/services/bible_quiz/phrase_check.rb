# frozen_string_literal: true

# Is this phrase in the Bible? Checked against the app's own verse text
# (ScriptureVerse: KJV, WEB and BSB), for "true_phrase" quiz questions —
# "Which of these does Scripture actually say?" — whose one right answer
# must be a verse and whose three decoys must NOT be (a player reported a
# question where "Love covers a multitude of sins", 1 Peter 4:8 WEB, was a
# decoy).
#
# A phrase matches a verse when, after normalizing (case, punctuation,
# "-eth"/"-est"/"-s" endings), the verse contains the phrase, or the verse
# has at least MIN_OVERLAP of the phrase's words AND a run of at least half
# of them in order. So "Pray without ceasing." matches 1 Thessalonians 5:17,
# while "Cleanliness is next to godliness" matches nothing.
#
#   BibleQuiz::PhraseCheck.new.match("Faith without works is dead")
#   # => #<data Match translation="kjv", book=59, chapter=2, verse=20, score=1.0>
module BibleQuiz
  class PhraseCheck
    MIN_OVERLAP = 0.85
    CANDIDATES = 150
    Match = Data.define(:translation, :book, :chapter, :verse, :score)

    def self.available?
      ScriptureVerse.table_exists? && ScriptureVerse.imported?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def initialize(translations: ScriptureVerse::TRANSLATIONS.keys)
      @translations = translations
      @cache = {}
    end

    # The best-matching verse, or nil when the phrase isn't in the Bible.
    def match(phrase)
      words = self.class.stems(phrase)
      return nil if words.empty?

      @cache.fetch(words) do
        @cache[words] = candidates(phrase).filter_map { |verse| scored(words, verse) }.max_by(&:score)
      end
    end

    def biblical?(phrase) = !match(phrase).nil?

    # "Love covereth the multitude!" → ["lov", "cover", "the", "multitude"]
    def self.stems(text)
      BibleQuizQuestion.normalize_text(text).delete(":").split.map { |w| stem(w) }
    end

    def self.stem(word)
      return word if word.length <= 3

      word = word.sub(/(?:eth|est|ing|ed|es|s)\z/, "") if word.length > 4
      word = word.sub(/e\z/, "") if word.length > 3
      word
    end

    private

    def scored(words, verse)
      text = self.class.stems(verse.text)
      return nil if text.empty?

      overlap = words.uniq.count { |w| text.include?(w) }.fdiv(words.uniq.size)
      run = longest_run(words, text)
      contained = run == words.size
      return nil unless contained || (overlap >= MIN_OVERLAP && run >= [ (words.size / 2.0).ceil, 2 ].max)

      Match.new(translation: verse.translation, book: verse.book, chapter: verse.chapter, verse: verse.verse,
                score: contained ? 1.0 : overlap)
    end

    # Longest stretch of the phrase's words that appears in the verse in order.
    def longest_run(words, text)
      best = 0
      prev = Array.new(text.size + 1, 0)
      words.each do |w|
        cur = Array.new(text.size + 1, 0)
        text.each_with_index do |t, j|
          next unless t == w

          cur[j + 1] = prev[j] + 1
          best = cur[j + 1] if cur[j + 1] > best
        end
        prev = cur
      end
      best
    end

    # Verses that could match: every verse with all of the phrase's search
    # terms — or all but one, so a slightly different wording still turns
    # up — best-ranked first. A phrase of only stop words ("I am that I am")
    # falls back to a plain text search.
    def candidates(phrase)
      scope = ScriptureVerse.where(translation: @translations)
      lexemes = ScriptureVerse.connection.select_value(
        ScriptureVerse.sanitize_sql_array([ "SELECT plainto_tsquery('english', ?)::text", phrase.to_s.first(300) ])
      ).to_s.scan(/'([^']+)'/).flatten.uniq.first(12)

      if lexemes.empty?
        like = "%#{ScriptureVerse.sanitize_sql_like(BibleQuizQuestion.normalize_text(phrase))}%"
        return scope.where("lower(text) LIKE ?", like).limit(CANDIDATES).to_a
      end

      groups = lexemes.size >= 3 ? lexemes.combination(lexemes.size - 1).to_a : [ lexemes ]
      query = groups.map { |g| "(#{g.map { |l| "'#{l.gsub("'", "''")}'" }.join(' & ')})" }.join(" | ")
      vector = "to_tsvector('english'::regconfig, text)"
      scope.where("#{vector} @@ to_tsquery('simple', ?)", query)
           .order(Arel.sql(ScriptureVerse.sanitize_sql_array([ "ts_rank(#{vector}, to_tsquery('simple', ?)) DESC", query ])))
           .limit(CANDIDATES)
           .to_a
    end
  end
end
