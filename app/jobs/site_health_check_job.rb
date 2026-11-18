# frozen_string_literal: true

# Every 10 minutes and after each deploy: open the main pages (SiteHealthCheck).
class SiteHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    failures = SiteHealthCheck.call
    Rails.logger.info("[SiteHealthCheck] #{failures.empty? ? 'all pages fine' : "#{failures.size} failing: #{failures.map(&:path).join(', ')}"}")
  end
end
