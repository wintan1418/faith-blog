# frozen_string_literal: true

# Nightly: resubmit the sitemap to Google (when Search Console is connected)
# and send IndexNow every public page that changed in the last day, which also
# catches anything an automatic batch missed.
class SearchIndexingNightlyJob < ApplicationJob
  queue_as :bulk

  WINDOW = 1.day

  def perform(*)
    SearchIndexingNightlyJob.submit_sitemap(trigger: "nightly") if SearchConsole.configured?
    return unless IndexNow.enabled?

    SearchIndexing.queue(SearchIndexing.recently_changed_urls(since: WINDOW.ago), source: "nightly")
    IndexNowFlushJob.perform_now("nightly")
  end

  # Submits the sitemap to Google and logs it. Returns the log row.
  def self.submit_sitemap(trigger:)
    SearchConsole.client.submit_sitemap
    IndexingSubmission.log!(engine: "google_sitemap", urls: [ SearchConsole::SITEMAP_URL ], status_code: 200,
                            response: "Submitted", trigger: trigger)
  rescue SearchConsole::Error => e
    IndexingSubmission.log!(engine: "google_sitemap", urls: [ SearchConsole::SITEMAP_URL ], status_code: nil,
                            response: e.message, trigger: trigger)
  end
end
