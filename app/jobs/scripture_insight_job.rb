# frozen_string_literal: true

# Writes and stores the insight for one scripture page (once). Enqueued in
# paced batches by `bin/rails scripture:insights`. Safe to run twice: a page
# that already has an insight is left alone, and nothing is written once
# ScriptureInsight::CAP pages exist. Never retried; a failure is counted by
# FeatureFailure and the page simply waits for the next batch.
class ScriptureInsightJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(slug, *) { "scripture-insight-#{slug}" }, duration: 5.minutes

  def perform(slug, force = false)
    reference = Scripture::Reference.from_slug(slug)
    return unless reference

    existing = ScriptureInsight.find_by(slug: reference.slug)
    return if existing && !force
    return if existing.nil? && ScriptureInsight.count >= ScriptureInsight::CAP
    # The offline stub has nothing real to say; never store its output.
    return if Ai::Moderation::Client.stub?

    passage = Scripture::Passage.new(reference)
    return unless passage.present?

    result = Ai::Bible::ScriptureInsightWriter.call(reference: reference, passage_text: passage.primary_text)
    insight = existing || ScriptureInsight.new(slug: reference.slug)
    insight.update!(reference: reference.plain, summary: result[:summary], explanation: result[:explanation],
                    context: result[:context], questions: result[:questions],
                    model: result[:model] || Ai::Moderation::Client.provider_name, generated_at: Time.current)
  rescue Ai::Moderation::Client::Error, Ai::Bible::ScriptureInsightWriter::ParseError => e
    Rails.logger.warn("[ScriptureInsightJob] #{slug}: #{e.class}: #{e.message}")
    FeatureFailure.record(:scripture_insights, "#{slug}: #{e.message}")
  rescue ActiveRecord::RecordNotUnique
    nil # another worker wrote it first
  end
end
