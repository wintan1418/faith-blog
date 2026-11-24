# frozen_string_literal: true

module Scripture
  # The 66 books of the Bible (KJV order and versification), read once from
  # config/scripture/books.yml: names, the abbreviations people type, and how
  # many verses each chapter has. Everything that turns text or a URL into a
  # reference asks this class whether that book, chapter and verse exist.
  module Canon
    Book = Data.define(:position, :name, :ref_name, :slug, :osis, :testament, :aliases, :verse_counts) do
      def chapters = verse_counts.size
      def verses_in(chapter) = verse_counts[chapter - 1].to_i
      def chapter?(chapter) = chapter.between?(1, chapters)
      def single_chapter? = chapters == 1
      def old_testament? = testament == "old"
      def to_s = name
    end

    BOOKS = YAML.load_file(Rails.root.join("config/scripture/books.yml")).each_with_index.map do |row, index|
      Book.new(position: index + 1, name: row["name"], ref_name: row["ref_name"], slug: row["slug"],
               osis: row["osis"], testament: row["testament"], aliases: row["aliases"].freeze,
               verse_counts: row["verses"].freeze)
    end.freeze

    ORDINALS = { "iii" => "3", "third" => "3", "3rd" => "3", "ii" => "2", "second" => "2", "2nd" => "2",
                 "i" => "1", "first" => "1", "1st" => "1" }.freeze

    # "1 Cor." / "I Corinthians" / "first-corinthians" / "1cor" all become "1corinthians"-style keys.
    def self.key(text)
      words = text.to_s.downcase.tr("-_.", "   ").split
      words[0] = ORDINALS.fetch(words[0], words[0]) if words.size > 1
      words.join.gsub(/[^a-z0-9]/, "")
    end

    LOOKUP = BOOKS.each_with_object({}) do |book, map|
      [ book.name, book.ref_name, book.slug, book.osis, *book.aliases ].each { |name| map[key(name)] ||= book }
    end.freeze

    def self.find(name)
      LOOKUP[key(name)]
    end

    def self.[](position)
      BOOKS[position.to_i - 1] if position.to_i.between?(1, BOOKS.size)
    end

    def self.old_testament = BOOKS.select(&:old_testament?)
    def self.new_testament = BOOKS.reject(&:old_testament?)
    def self.chapter_count = BOOKS.sum(&:chapters)
  end
end
