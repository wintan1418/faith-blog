# frozen_string_literal: true

# Writes and stores the prayer burden for one Bible chapter. Enqueued lazily
# the first time a member finishes a chapter whose burden is missing or from
# an older ChapterPrayer::VERSION (ChapterPrayer.request), or in paced batches
# by `bin/rails "bible_today:prayers[200]"`. Safe to run twice: a chapter
# whose burden is current is left alone unless forced. Never retried (the
# writer already retries the AI): a failure is counted by FeatureFailure and
# the chapter keeps what it had (an older prayer, or the fallback).
class ChapterPrayerJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(slug, *) { "chapter-prayer-#{slug}" }, duration: 5.minutes

  def perform(slug, force = false)
    chapter = Scripture::Reference.from_slug(slug.to_s)&.chapter_reference
    return unless chapter

    existing = ChapterPrayer.find_by(slug: chapter.slug)
    return if existing&.current? && !force
    return if existing.nil? && ChapterPrayer.count >= ChapterPrayer::CAP
    # The offline stub has nothing real to say; never store its output.
    return if Ai::Moderation::Client.stub?

    passage = Scripture::Passage.new(chapter)
    return unless passage.present?

    result = Ai::Bible::ChapterPrayerWriter.call(reference: chapter, texts: passage.texts)
    prayer = existing || ChapterPrayer.new(slug: chapter.slug)
    prayer.update!(
      reference: chapter.plain, version: ChapterPrayer::VERSION,
      burden: result[:burden], body: result[:prayer], themes: result[:themes],
      points: result[:points].map { |p| p.transform_keys(&:to_s) },
      key_verses: result[:key_verses], verses: result[:key_verses],
      model: result[:model] || Ai::Moderation::Client.provider_name, generated_at: Time.current
    )
  rescue Ai::Moderation::Client::Error, Ai::Bible::ChapterPrayerWriter::ParseError => e
    Rails.logger.warn("[ChapterPrayerJob] #{slug}: #{e.class}: #{e.message}")
    FeatureFailure.record(:chapter_prayers, "#{slug}: #{e.message}")
  rescue ActiveRecord::RecordNotUnique
    nil # another worker wrote it first
  end
end
