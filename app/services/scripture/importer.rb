# frozen_string_literal: true

require "zlib"

module Scripture
  # Loads the public-domain Bible text (KJV, WEB, BSB) and the cross-references
  # from db/scripture/*.tsv.gz into the database. Safe to re-run: a translation
  # that is already complete is skipped (pass force: true to reload).
  class Importer
    DATA_DIR = Rails.root.join("db/scripture")
    BATCH = 5_000

    def self.call(force: false, io: $stdout)
      new(force: force, io: io).call
    end

    def initialize(force:, io:)
      @force = force
      @io = io
    end

    def call
      ScriptureVerse::TRANSLATIONS.each_key { |code| import_translation(code) }
      import_cross_references
    end

    private

    def import_translation(code)
      file = DATA_DIR.join("#{code}.tsv.gz")
      expected = line_count(file)
      existing = ScriptureVerse.where(translation: code).count
      if existing == expected && !@force
        say "#{code.upcase}: #{existing} verses already loaded"
        return
      end

      ScriptureVerse.transaction do
        ScriptureVerse.where(translation: code).delete_all
        each_row(file) do |rows|
          ScriptureVerse.insert_all(rows.map do |book, chapter, verse, text|
            { translation: code, book: book.to_i, chapter: chapter.to_i, verse: verse.to_i, text: text }
          end)
        end
      end
      say "#{code.upcase}: loaded #{expected} verses"
    end

    def import_cross_references
      file = DATA_DIR.join("cross_references.tsv.gz")
      expected = line_count(file)
      if ScriptureCrossReference.count == expected && !@force
        say "Cross-references: #{expected} already loaded"
        return
      end

      ScriptureCrossReference.transaction do
        ScriptureCrossReference.delete_all
        each_row(file) do |rows|
          ScriptureCrossReference.insert_all(rows.map do |b, c, v, tb, tc, tv, tce, tve, votes|
            { book: b.to_i, chapter: c.to_i, verse: v.to_i, to_book: tb.to_i, to_chapter: tc.to_i, to_verse: tv.to_i,
              to_chapter_end: tce.presence&.to_i, to_verse_end: tve.presence&.to_i, votes: votes.to_i }
          end)
        end
      end
      say "Cross-references: loaded #{expected}"
    end

    def each_row(file)
      batch = []
      Zlib::GzipReader.open(file) do |gz|
        gz.each_line do |line|
          batch << line.chomp.split("\t", -1)
          next if batch.size < BATCH

          yield batch
          batch = []
        end
      end
      yield batch if batch.any?
    end

    def line_count(file)
      Zlib::GzipReader.open(file) { |gz| gz.each_line.count }
    end

    def say(message)
      @io&.puts(message)
    end
  end
end
