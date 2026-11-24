# frozen_string_literal: true

module Scripture
  # Which scripture pages we tell search engines about, and the order their
  # insights get written in: the most-searched verses first, then verses
  # members quote, the verse-of-the-day pool, and finally every chapter.
  module Catalog
    POPULAR_FILE = Rails.root.join("config/scripture/popular_verses.yml")

    module_function

    def popular
      @popular ||= YAML.load_file(POPULAR_FILE).filter_map { |text| Reference.parse(text) }.uniq(&:slug).freeze
    end

    def popular_slugs
      @popular_slugs ||= popular.to_set(&:slug).freeze
    end

    def chapters
      @chapters ||= Canon::BOOKS.flat_map { |book| (1..book.chapters).map { |c| Reference.chapter(book, c) } }.freeze
    end

    # References quoted by breaths a scripture page would show.
    def cited
      ScriptureCitation.where(post_id: Post.scripture_discussable.select(:id))
                       .distinct.pluck(:book, :chapter, :verse_start, :verse_end)
                       .filter_map { |b, c, vs, ve| Reference.build(Canon[b], c, vs, ve) }
    end

    def daily
      BibleVerse.active.pluck(:reference).filter_map { |text| Reference.parse(text) }
    end

    # Priority order for writing insights.
    def queue
      unique(popular + cited + daily + chapters)
    end

    # Every page in the sitemap.
    def sitemap
      written = ScriptureInsight.pluck(:slug).filter_map { |slug| Reference.from_slug(slug) }
      unique(chapters + popular + cited + daily + written)
    end

    # Popular verses inside one chapter (for links on the chapter page).
    def popular_in(book, chapter)
      popular.select { |ref| ref.book == book && ref.chapter == chapter && !ref.chapter? }.sort
    end

    def unique(refs)
      refs.compact.uniq(&:slug)
    end
  end
end
