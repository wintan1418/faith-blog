# frozen_string_literal: true

# "Read your Bible, pray every day": the prayer burden for one Bible chapter.
# Today's burden (what the chapter calls us to pray about), 3-5 prayer points
# each tied to a verse of the chapter, a short closing prayer (body), and the
# themes and key verses they came from. Written by ChapterPrayerJob (lazily
# on first view, or in batches with `bin/rails "bible_today:prayers[200]"`)
# and stored; pages never wait for the AI.
#
# VERSION marks the shape and depth of what's stored. A row from an older
# version is still shown (its short prayer) while a fresh one is written;
# a chapter with no row yet gets the fallback.
class ChapterPrayer < ApplicationRecord
  # 2: the deep, chapter-specific burden (November 2026). 1 was one short prayer.
  VERSION = 2
  # There are 1,189 chapters; never write more than that (cost guard).
  CAP = 1_189
  # Don't enqueue the same chapter again for this long while one is pending.
  REQUEST_TTL = 30.minutes

  KIND_LABELS = {
    "praise" => "Praise", "thanksgiving" => "Thanks", "confession" => "Confess", "lament" => "Lament",
    "trust" => "Trust", "intercession" => "Intercede", "application" => "Obey"
  }.freeze

  # One prayer point: a line to pray and the verse it comes from.
  Point = Data.define(:text, :reference, :kind) do
    def label = KIND_LABELS[kind]
    def anchor = "v#{reference.verse_start}"
  end

  # What the page shows: a current stored burden (stored? and current?), an
  # older stored prayer while the new one is written, or the fallback.
  Shown = Data.define(:reference, :burden, :points, :body, :verses, :themes, :stored, :current) do
    def stored? = stored
    def current? = current
    # The key verses as Scripture::References (for links).
    def verse_references = verses.filter_map { |v| Scripture::Reference.parse(v) }
    def points? = points.any?
  end

  scope :outdated, -> { where(version: ...VERSION) }

  validates :slug, :reference, :body, :generated_at, presence: true
  validates :slug, uniqueness: true

  # The prayer to show after reading `chapter` (a chapter Reference). Never
  # blocks: when none is stored yet, or the stored one is an older version, it
  # asks for a new one in the background and shows what it has meanwhile.
  def self.for(chapter)
    chapter = chapter.chapter_reference
    stored = find_by(slug: chapter.slug)
    return stored.shown if stored&.current?

    request(chapter, refresh: stored.present?)
    stored ? stored.shown : fallback(chapter)
  rescue StandardError => e
    Rails.logger.warn("[chapter_prayer] #{chapter&.slug}: #{e.class}: #{e.message}")
    fallback(chapter)
  end

  # A plain prayer that fits any chapter while its own is written: it asks, it
  # never speaks for God, and it doesn't pretend to know what the chapter said.
  def self.fallback(chapter)
    burden = "Ask God to show you who he is in #{chapter}, and what he is asking of you today."
    body = "Lord, I have read #{chapter} and I want more than words on a page. " \
           "Show me what this chapter shows me about you, and where it calls me to change. " \
           "Where I do not yet understand, give me patience and a teachable heart. " \
           "Bring the people on my heart before you today, and help me to obey what I have seen. Amen."
    Shown.new(reference: chapter, burden: burden, points: [], body: body, verses: [], themes: [], stored: false, current: false)
  end

  # Ask for this chapter's burden once (per REQUEST_TTL). If the cache store is
  # unavailable the job is enqueued anyway: it is idempotent and keyed per chapter.
  def self.request(chapter, refresh: false)
    return if Ai::Moderation::Client.stub?
    return if !refresh && count >= CAP

    first_ask = begin
      Rails.cache.write([ "chapter-prayer-requested", VERSION, chapter.slug ], true, expires_in: REQUEST_TTL, unless_exist: true)
    rescue StandardError
      true
    end
    ChapterPrayerJob.perform_later(chapter.slug) if first_ask
  end

  def current? = version.to_i >= VERSION

  def shown
    chapter = Scripture::Reference.from_slug(slug).chapter_reference
    Shown.new(reference: chapter, burden: current? ? burden.to_s : nil, points: current? ? point_list : [],
              body: body, verses: verse_list, themes: current? ? Array(themes).map(&:to_s) : [], stored: true, current: current?)
  end

  def point_list
    Array(points).filter_map do |point|
      ref = Scripture::Reference.parse(point["reference"].to_s)
      next unless ref && point["text"].present?

      Point.new(text: point["text"].to_s, reference: ref, kind: point["kind"].to_s)
    end
  end

  def verse_list = Array(key_verses.presence || verses).map(&:to_s).compact_blank.first(3)
end
