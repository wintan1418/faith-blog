# frozen_string_literal: true

module Scripture
  # One Bible reference: a whole chapter (Psalm 23), a verse (Psalm 101:3) or
  # a range inside one chapter (Genesis 1:11-12). Only references that exist
  # in the KJV can be built, so every Reference has a page.
  #
  #   Reference.parse("Ps. 101:3")             # => Psalm 101:3
  #   Reference.parse("ephesians chapter 1 verse 3")
  #   Reference.from_slug("genesis-1-11-to-12") # => Genesis 1:11-12
  #   ref.slug                                  # => "genesis-1-11-12"
  Reference = Data.define(:book, :chapter, :verse_start, :verse_end)

  class Reference
    include Comparable

    # Turn whatever someone typed into a Reference, or nil.
    def self.parse(text)
      cleaned = text.to_s.downcase.tr("–—", "--").strip
      cleaned = cleaned.gsub(/\b(?:chapter|chap|ch)\b\.?/, " ")
                       .gsub(/\s*\b(?:verses?|vv?)\b\.?\s*/, ":")
                       .gsub(/\s*\b(?:to|through|thru)\b\s*/, "-")
                       .squeeze(" ").strip
      match = cleaned.match(/\A(?<book>(?:[1-3]|i{1,3}|first|second|third)?\s*[a-z][a-z.\s]*?)\s*(?<ch>\d{1,3})(?:\s*[:.\s]\s*(?<v1>\d{1,3})(?:\s*-\s*(?<v2>\d{1,3}))?)?\z/)
      return nil unless match

      build(Canon.find(match[:book]), match[:ch], match[:v1], match[:v2])
    end

    # "/scripture/psalm-101-3", "psalms-23", "1-cor-13-4-to-7" → Reference.
    # The page then redirects to `slug` when the two differ.
    def self.from_slug(slug)
      parts = slug.to_s.downcase.split(/[-_\s]+/).compact_blank - %w[chapter ch verse verses v to through]
      numbers = []
      numbers.unshift(parts.pop) while parts.size > 1 && parts.last.match?(/\A\d{1,3}\z/) && numbers.size < 3
      return nil if numbers.empty? || parts.empty?

      build(Canon.find(parts.join(" ")), *numbers)
    end

    def self.build(book, chapter, verse_start = nil, verse_end = nil)
      return nil unless book

      chapter = chapter.to_i
      verse_start = verse_start&.to_i
      verse_end = verse_end&.to_i
      # "Jude 3" means verse 3 of Jude's only chapter.
      if book.single_chapter? && verse_start.nil? && chapter > 1
        verse_start = chapter
        chapter = 1
      end
      return nil unless book.chapter?(chapter)

      if verse_start
        last = book.verses_in(chapter)
        return nil unless verse_start.between?(1, last)

        verse_end = nil if verse_end.nil? || verse_end <= verse_start
        verse_end = [ verse_end, last ].min if verse_end
      else
        verse_end = nil
      end
      new(book: book, chapter: chapter, verse_start: verse_start, verse_end: verse_end)
    end

    def self.chapter(book, chapter) = build(book, chapter)

    def chapter? = verse_start.nil?
    def range? = !verse_end.nil?
    def last_verse = verse_end || verse_start
    def verses = chapter? ? (1..book.verses_in(chapter)) : (verse_start..last_verse)
    def verse_count = verses.size

    # "psalm-101-3", "genesis-1-11-12", "psalm-23".
    def slug
      [ book.slug, chapter, verse_start, verse_end ].compact.join("-")
    end
    alias_method :to_param, :slug

    # "Psalm 101:3", "Genesis 1:11–12" (display).
    def to_s = label(dash: "–")

    # "Genesis 1:11-12" — plain hyphen, for prompts, lookups and storage.
    def plain = label(dash: "-")

    def label(dash:)
      text = "#{book.ref_name} #{chapter}"
      text += ":#{verse_start}" if verse_start
      text += "#{dash}#{verse_end}" if verse_end
      text
    end

    def chapter_reference = Reference.chapter(book, chapter)

    def <=>(other)
      sort_key <=> other.sort_key
    end

    def sort_key = [ book.position, chapter, verse_start || 0, verse_end || 0 ]

    # The verse or chapter just before / after this one, across chapter and book lines.
    def previous
      if chapter?
        return Reference.chapter(book, chapter - 1) if chapter > 1

        prior = Canon[book.position - 1]
        prior && Reference.chapter(prior, prior.chapters)
      else
        return Reference.build(book, chapter, verse_start - 1) if verse_start > 1
        return Reference.build(book, chapter - 1, book.verses_in(chapter - 1)) if chapter > 1

        prior = Canon[book.position - 1]
        prior && Reference.build(prior, prior.chapters, prior.verses_in(prior.chapters))
      end
    end

    def next
      if chapter?
        return Reference.chapter(book, chapter + 1) if chapter < book.chapters

        following = Canon[book.position + 1]
        following && Reference.chapter(following, 1)
      else
        return Reference.build(book, chapter, last_verse + 1) if last_verse < book.verses_in(chapter)
        return Reference.build(book, chapter + 1, 1) if chapter < book.chapters

        following = Canon[book.position + 1]
        following && Reference.build(following, 1, 1)
      end
    end

    # Book names and abbreviations as they appear in writing: "Psalm 101:3",
    # "1 Cor. 13:4-7", "Romans 8". Bare chapters only count for unambiguous
    # names ("Mark 2", "Acts 2" or "John 3" are too often ordinary words).
    AMBIGUOUS_CHAPTER_NAMES = %w[mark acts job numbers ruth jude james john amos titus judges].freeze

    BOOK_PATTERN = begin
      names = Canon::BOOKS.flat_map do |book|
        [ book.name, book.ref_name, (book.ref_name + "s" if book.name == "Psalms"),
          *book.aliases.select { |a| a.length >= 3 && a !~ /\A\d/ }.map { |a| a.capitalize },
          *book.aliases.select { |a| a.match?(/\A\d[a-z]{2,}/) }.map { |a| "#{a[0]} #{a[1..].capitalize}" } ]
      end.compact.uniq
      words = names.map { |n| n.sub(/\A([1-3]) /, "") }.uniq.sort_by { |n| -n.length }
      body = words.map { |w| Regexp.escape(w).gsub("\\ ", "\\s+") }.join("|")
      "(?:(?:[1-3]|I{1,3})\\s*)?(?:#{body})\\.?"
    end
    TEXT_REGEX = /(?<![\w-])(?<book>#{BOOK_PATTERN})\s+(?<ch>\d{1,3})(?::(?<v1>\d{1,3})(?:\s*[-–]\s*(?<v2>\d{1,3}))?)?(?![\w:])/i

    # Every reference in a piece of text, with where it sits:
    # [[Reference, start, finish, matched_text], ...]
    def self.scan(text)
      found = []
      text.to_s.scan(TEXT_REGEX) do
        m = Regexp.last_match
        book = Canon.find(m[:book])
        next unless book
        next if m[:v1].nil? && (book.single_chapter? || AMBIGUOUS_CHAPTER_NAMES.include?(book.slug))

        ref = build(book, m[:ch], m[:v1], m[:v2])
        found << [ ref, m.begin(0), m.end(0), m[0] ] if ref
      end
      found
    end

    def self.find_all(text) = scan(text).map(&:first).uniq
  end
end
