# frozen_string_literal: true

# Daily (and on "Refresh now"): pull the Search Console reports into the database.
class SearchConsoleRefreshJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(*) { "search_console_refresh" }, duration: 10.minutes

  def perform(*)
    return unless SearchConsole.configured?

    errors = SearchConsole::Refresh.call
    Rails.logger.info("[SearchConsole] refreshed#{" with errors: #{errors.uniq.join('; ')}" if errors.any?}")
  rescue SearchConsole::Error => e
    SearchConsoleReport.store!("status", data: { "ok" => false }, error: e.message)
  end
end
