# frozen_string_literal: true

module SiteSearch
  # What someone typed, understood:
  #
  #   shepherd psalm        both words (stemmed: "shepherds" matches too)
  #   "good shepherd"       the exact phrase
  #   grace -law            grace, but not law
  #   from:grace_okafor     only breaths signed by that member
  #   prayi                 the last word also matches as a prefix (typing)
  #
  # Text is NFKC-normalized first, so 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿 typed in "fancy" letters is
  # the plain word teenager. The tsquery is assembled from letters and digits
  # only, so nothing a user types can inject tsquery (or SQL) syntax.
  class Query
    MAX_LENGTH = 200
    MAX_TERMS = 12
    WORD = /[\p{L}\p{M}\p{N}]+/
    FROM = /(?:^|\s)from:@?([\w.\-]{1,40})/i

    attr_reader :raw, :text, :from_username, :terms, :phrases, :excluded

    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkc).gsub(/[[:cntrl:]\u{E000}-\u{F8FF}]/, " ").squish.first(MAX_LENGTH)
    rescue ArgumentError, Encoding::CompatibilityError
      value.to_s.scrub("").squish.first(MAX_LENGTH)
    end

    def initialize(raw, prefix: true)
      @raw = raw.to_s
      @prefix = prefix
      # "grace " (a space typed after the word) means the word is finished.
      @finished = @raw.match?(/\s\z/)
      @text = self.class.normalize(@raw)
      parse
    end

    # Words and phrases that must match (the query is useless without one).
    def searchable? = tsquery.present?
    def blank? = text.blank?

    # The words alone, without from: and exclusions: what an exact-title match
    # compares against, and what "Did you mean" corrects.
    def plain_text
      (phrases + terms).join(" ")
    end

    # e.g. 'good' <-> 'shepherd' & 'psalm':* & !'law'
    def tsquery
      @tsquery ||= begin
        positive = phrases.filter_map { |p| phrase_clause(p) }
        last = terms.size - 1
        positive += terms.each_with_index.filter_map do |term, i|
          tokens = term.scan(WORD)
          next if tokens.empty?

          clause = tokens.map { |t| quote(t) }.join(" <-> ")
          clause += ":*" if @prefix && i == last && tokens.size == 1 && term.length >= 2 && !@finished
          clause
        end
        if positive.empty?
          ""
        else
          negative = excluded.filter_map { |e| (tokens = e.scan(WORD)).any? ? "!(#{tokens.map { |t| quote(t) }.join(' <-> ')})" : nil }
          (positive.map { |c| c.include?("<->") ? "(#{c})" : c } + negative).join(" & ")
        end
      end
    end

    # The same query without the trailing prefix (for headlines and ranking
    # tests that want whole words).
    def words
      terms + phrases
    end

    def with_text(new_text)
      self.class.new([ new_text, (from_username && "from:#{from_username}") ].compact.join(" "), prefix: @prefix)
    end

    private

    def parse
      rest = text.dup
      @from_username = rest[FROM, 1]&.downcase
      rest = rest.gsub(FROM, " ")
      @phrases = rest.scan(/"([^"]+)"/).flatten.map(&:squish).compact_blank.first(MAX_TERMS)
      rest = rest.gsub(/"[^"]*"?/, " ")
      tokens = rest.split
      @excluded = tokens.select { |t| t.start_with?("-") && t.length > 1 }.map { |t| t.delete_prefix("-") }.first(MAX_TERMS)
      @terms = (tokens.reject { |t| t.start_with?("-") }.map { |t| t.gsub(/\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/, "") }
                      .compact_blank).first(MAX_TERMS)
    end

    def phrase_clause(phrase)
      tokens = phrase.scan(WORD)
      tokens.any? ? tokens.map { |t| quote(t) }.join(" <-> ") : nil
    end

    # Tokens are letters/digits only, so a plain quote is enough.
    def quote(token) = "'#{token.downcase}'"
  end
end
