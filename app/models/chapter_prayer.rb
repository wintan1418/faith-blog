# frozen_string_literal: true

# "Read your Bible, pray every day": a short first-person prayer drawn from one
# Bible chapter, with the verses it leans on. Written once per chapter by
# ChapterPrayerJob (lazily on first request, or in batches with
# `bin/rails "bible_today:prayers[200]"`) and stored; pages never wait for the
# AI. Until a chapter's prayer exists, members get a plain fallback prayer.
class ChapterPrayer < ApplicationRecord
  # There are 1,189 chapters; never write more than that (cost guard).
  CAP = 1_189
  # Don't enqueue the same chapter again for this long while one is pending.
  REQUEST_TTL = 30.minutes

  # What the page shows: a stored prayer, or the fallback (stored? false).
  Shown = Data.define(:reference, :body, :verses, :stored) do
    def stored? = stored
    # The verse references as Scripture::References (for links).
    def verse_references = verses.filter_map { |v| Scripture::Reference.parse(v) }
  end

  validates :slug, :reference, :body, :generated_at, presence: true
  validates :slug, uniqueness: true

  # The prayer to show after reading `chapter` (a chapter Reference). Never
  # blocks: when none is stored yet it asks for one in the background and
  # returns the fallback.
  def self.for(chapter)
    chapter = chapter.chapter_reference
    stored = find_by(slug: chapter.slug)
    return Shown.new(reference: chapter, body: stored.body, verses: stored.verse_list, stored: true) if stored

    request(chapter)
    fallback(chapter)
  rescue StandardError => e
    Rails.logger.warn("[chapter_prayer] #{chapter&.slug}: #{e.class}: #{e.message}")
    fallback(chapter)
  end

  # A plain prayer that fits any chapter: it asks, it never speaks for God.
  def self.fallback(chapter)
    body = "Lord, thank you for speaking through #{chapter} today. " \
           "Help me to remember what I have read and to carry it into this day. " \
           "Where I do not yet understand, give me patience and a teachable heart. " \
           "Let my words and choices be shaped by your Word. Amen."
    Shown.new(reference: chapter, body: body, verses: [], stored: false)
  end

  # Ask for this chapter's prayer once (per REQUEST_TTL). If the cache store is
  # unavailable the job is enqueued anyway: it is idempotent and keyed per chapter.
  def self.request(chapter)
    return if Ai::Moderation::Client.stub?
    return if count >= CAP

    first_ask = begin
      Rails.cache.write([ "chapter-prayer-requested", chapter.slug ], true, expires_in: REQUEST_TTL, unless_exist: true)
    rescue StandardError
      true
    end
    ChapterPrayerJob.perform_later(chapter.slug) if first_ask
  end

  def verse_list = Array(verses).map(&:to_s).compact_blank.first(3)
end
