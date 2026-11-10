# frozen_string_literal: true

# Keeps site analytics to the last 13 months.
class AnalyticsCleanupJob < ApplicationJob
  queue_as :default

  KEEP = 13.months

  def perform
    cutoff = KEEP.ago
    Ahoy::Event.where(time: ...cutoff).in_batches(of: 5_000).delete_all
    Ahoy::Visit.where(started_at: ...cutoff).in_batches(of: 5_000).delete_all
  end
end
