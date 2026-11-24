# frozen_string_literal: true

# Sends the URLs waiting in indexing_pending_urls to IndexNow, 10,000 per
# request. Queued a few minutes after the first change so a burst of edits
# goes out as one batch. URLs stay queued when IndexNow is down or busy
# (5xx/429/no answer) and are retried by the next flush or the nightly job;
# URLs that wait more than three days are dropped.
class IndexNowFlushJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(*) { "indexnow_flush" }, duration: 10.minutes

  GIVE_UP_AFTER = 3.days

  def perform(trigger = "auto")
    return unless IndexNow.enabled?

    IndexingPendingUrl.where(created_at: ...GIVE_UP_AFTER.ago).delete_all
    loop do
      batch = IndexingPendingUrl.order(:id).limit(IndexNow::MAX_URLS).pluck(:id, :url)
      break if batch.empty?

      submissions = IndexNow.submit(batch.map(&:last), trigger: trigger)
      break if submissions.any? { |s| retry_later?(s.status_code) }

      IndexingPendingUrl.where(id: batch.map(&:first)).delete_all
      break if batch.size < IndexNow::MAX_URLS
    end
  end

  private

  def retry_later?(status)
    status.nil? || status == 429 || status >= 500
  end
end
