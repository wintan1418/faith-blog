# frozen_string_literal: true

module Scripture
  # The text of a reference in every translation we hold, plus (for a verse)
  # the KJV verses around it. One query; falls back to the live KJV lookup
  # when the Bible text hasn't been imported yet.
  class Passage
    CONTEXT = 2 # verses either side shown as "in context"

    attr_reader :reference

    def initialize(reference)
      @reference = reference
      load!
    end

    # { "kjv" => [[1, "In the beginning…"], …], "web" => […], "bsb" => […] }
    def texts = @texts
    def translations = @texts.keys
    def primary = @texts[ScriptureVerse::PRIMARY] || @texts.values.first || []
    def present? = primary.any?
    def primary_text = primary.map(&:last).join(" ")

    # KJV verses just around a single verse/range ([[n, text], …]), or [].
    def surrounding = @surrounding

    private

    def load!
      @texts = {}
      @surrounding = []
      span = reference.verses
      unless reference.chapter?
        first = [ span.first - CONTEXT, 1 ].max
        last = [ span.last + CONTEXT, reference.book.verses_in(reference.chapter) ].min
        span = (first..last)
      end

      rows = ScriptureVerse.where(book: reference.book.position, chapter: reference.chapter, verse: span)
                           .order(:verse).pluck(:translation, :verse, :text)
      return load_live! if rows.empty?

      wanted = reference.verses
      ScriptureVerse::TRANSLATIONS.each_key do |code|
        verses = rows.select { |t, v, _| t == code && wanted.cover?(v) }.map { |_, v, text| [ v, text ] }
        @texts[code] = verses if verses.any?
      end
      @surrounding = rows.select { |t, _, _| t == ScriptureVerse::PRIMARY }.map { |_, v, text| [ v, text ] } unless reference.chapter?
    end

    def load_live!
      payload = ScriptureLookup.lookup(reference.plain)
      verses = Array(payload&.dig(:verses)).map { |v| [ v[:verse].to_i, v[:text].to_s.strip ] }
      verses = [ [ reference.verse_start || 1, payload[:text].to_s.strip ] ] if verses.empty? && payload&.dig(:text).present?
      @texts[ScriptureVerse::PRIMARY] = verses if verses.any?
    end
  end
end
