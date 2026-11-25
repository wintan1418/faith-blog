# frozen_string_literal: true

# Writes and stores the prayer for one Bible chapter (once). Enqueued lazily
# the first time a member finishes a chapter that has none yet
# (ChapterPrayer.request), or in paced batches by
# `bin/rails "bible_today:prayers[200]"`. Safe to run twice. Never retried: a
# failure is counted by FeatureFailure and the chapter keeps its fallback.
class ChapterPrayerJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(slug, *) { "chapter-prayer-#{slug}" }, duration: 5.minutes

  def perform(slug, force = false)
    chapter = Scripture::Reference.from_slug(slug.to_s)&.chapter_reference
    return unless chapter

    existing = ChapterPrayer.find_by(slug: chapter.slug)
    return if existing && !force
    return if existing.nil? && ChapterPrayer.count >= ChapterPrayer::CAP
    # The offline stub has nothing real to say; never store its output.
    return if Ai::Moderation::Client.stub?

    passage = Scripture::Passage.new(chapter)
    return unless passage.present?

    result = Ai::Bible::ChapterPrayerWriter.call(reference: chapter, passage_text: passage.primary_text)
    prayer = existing || ChapterPrayer.new(slug: chapter.slug)
    prayer.update!(reference: chapter.plain, body: result[:prayer], verses: result[:verses],
                   model: result[:model] || Ai::Moderation::Client.provider_name, generated_at: Time.current)
  rescue Ai::Moderation::Client::Error, Ai::Bible::ChapterPrayerWriter::ParseError => e
    Rails.logger.warn("[ChapterPrayerJob] #{slug}: #{e.class}: #{e.message}")
    FeatureFailure.record(:chapter_prayers, "#{slug}: #{e.message}")
  rescue ActiveRecord::RecordNotUnique
    nil # another worker wrote it first
  end
end
