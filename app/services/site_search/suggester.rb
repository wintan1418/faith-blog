# frozen_string_literal: true

module SiteSearch
  # "Did you mean …?" Each word that isn't a known word is swapped for the
  # closest known one (pg_trgm similarity), preferring common words. Known
  # words come from public breaths only (SearchTermsRefreshJob), so a
  # suggestion can never reveal a word from a private room.
  class Suggester
    MIN_SIMILARITY = 0.4
    KNOWN_NDOC = 3

    def initialize(query)
      @query = query
    end

    # The corrected text, or nil when nothing changes.
    def suggestion
      words = @query.terms
      return nil if words.empty? || words.size > 6

      corrected = words.map { |w| correct(w) || w }
      return nil if corrected.map(&:downcase) == words.map(&:downcase)

      (@query.phrases.map { |p| %("#{p}") } + corrected).join(" ")
    end

    private

    def correct(word)
      return nil if word.length < 3 || word.length > 40 || word.match?(/\d/)

      conn = ActiveRecord::Base.connection
      folded = "public.search_fold(#{conn.quote(word)})"
      known = conn.select_value("SELECT ndoc FROM search_terms WHERE term = #{folded}")
      return nil if known.to_i >= KNOWN_NDOC

      conn.select_value(<<~SQL)
        SELECT term FROM search_terms
        WHERE term % #{folded} AND term <> #{folded} AND similarity(term, #{folded}) >= #{MIN_SIMILARITY}
        ORDER BY similarity(term, #{folded}) DESC, ndoc DESC
        LIMIT 1
      SQL
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("[search] suggestion failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
