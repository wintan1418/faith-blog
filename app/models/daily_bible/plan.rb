# frozen_string_literal: true

module DailyBible
  # The reading plans behind "Have you read your Bible today?". Each plan is
  # an ordered list of portions (one day's reading: one or more whole
  # chapters), built from the canon in Scripture::Canon, so every portion
  # links to chapter pages that exist.
  #
  # A member's place in a plan is just "portions finished": a missed day never
  # skips anything, today's reading is simply the next unread portion.
  class Plan
    # One day's reading. `chapters` are Scripture::Reference chapters.
    Portion = Data.define(:index, :chapters) do
      def first = chapters.first
      def last = chapters.last
      def include?(reference) = chapters.any? { |c| c.book == reference.book && c.chapter == reference.chapter }
      def single? = chapters.size == 1
      def verse_count = chapters.sum(&:verse_count)
      # About 25 words a verse, read at a calm 230 words a minute.
      def minutes = [ (verse_count * 25 / 230.0).ceil, 1 ].max

      # "John 3", "Genesis 1–3", "Psalm 1 · Proverbs 1", "Ruth 4 · 1 Samuel 1–2".
      def label
        chapters.chunk_while { |a, b| a.book == b.book && b.chapter == a.chapter + 1 }.map do |run|
          name = run.first.book.ref_name
          run.size == 1 ? "#{name} #{run.first.chapter}" : "#{name} #{run.first.chapter}–#{run.last.chapter}"
        end.join(" · ")
      end
    end

    DEFAULT_SLUG = "chapter-a-day"

    attr_reader :slug, :title, :blurb

    def initialize(slug:, title:, blurb:, repeats: false, &builder)
      @slug = slug
      @title = title
      @blurb = blurb
      @repeats = repeats
      @builder = builder
    end

    # A plan that starts again from the top once finished (the default plan).
    def repeats? = @repeats

    def portions
      @portions ||= @builder.call.each_with_index.map { |chapters, i| Portion.new(index: i, chapters: chapters.freeze) }.freeze
    end

    def size = portions.size

    # The portion after `finished` portions, or nil when the plan is done.
    def portion_at(finished)
      finished = finished.to_i
      finished %= size if repeats? && size.positive?
      portions[finished]
    end

    def finished?(finished) = !repeats? && finished.to_i >= size

    def self.all = PLANS
    def self.find(slug) = PLANS.find { |plan| plan.slug == slug.to_s }
    def self.default = find(DEFAULT_SLUG)
    def self.slugs = PLANS.map(&:slug)

    # ── Building blocks ───────────────────────────────────────────────

    def self.chapters_of(*book_names)
      book_names.flat_map do |name|
        book = Scripture::Canon.find(name)
        (1..book.chapters).map { |n| Scripture::Reference.chapter(book, n) }
      end
    end

    def self.all_chapters(books) = books.flat_map { |book| (1..book.chapters).map { |n| Scripture::Reference.chapter(book, n) } }

    # Split `chapters` into `days` portions of nearly equal size, in order.
    def self.spread(chapters, days)
      (0...days).map do |day|
        chapters[(day * chapters.size / days)...((day + 1) * chapters.size / days)]
      end.reject(&:empty?)
    end

    john = Scripture::Canon.find("John")

    PLANS = [
      new(slug: "chapter-a-day", title: "A chapter a day",
          blurb: "Start with John, then the rest of the New Testament, then the Old. One chapter a day.",
          repeats: true) do
        nt = all_chapters(Scripture::Canon.new_testament)
        (nt.select { |c| c.book == john } + nt.reject { |c| c.book == john } +
          all_chapters(Scripture::Canon.old_testament)).map { |c| [ c ] }
      end,
      new(slug: "gospels-89", title: "The Gospels in 89 days",
          blurb: "Matthew, Mark, Luke and John: the life of Jesus, a chapter a day.") do
        chapters_of("Matthew", "Mark", "Luke", "John").map { |c| [ c ] }
      end,
      new(slug: "new-testament-year", title: "New Testament in a year",
          blurb: "All 260 chapters, one a day, five days a week. Read at weekends to finish sooner.") do
        all_chapters(Scripture::Canon.new_testament).map { |c| [ c ] }
      end,
      new(slug: "bible-year", title: "Whole Bible in a year",
          blurb: "Genesis to Revelation in 365 days: three or four chapters a day.") do
        spread(all_chapters(Scripture::Canon::BOOKS), 365)
      end,
      new(slug: "psalms-proverbs", title: "Psalms & Proverbs",
          blurb: "A psalm and a proverb each day, for 150 days.") do
        psalms = chapters_of("Psalms")
        proverbs = chapters_of("Proverbs")
        psalms.each_with_index.map { |psalm, i| [ psalm, proverbs[i % proverbs.size] ] }
      end
    ].freeze
  end
end
