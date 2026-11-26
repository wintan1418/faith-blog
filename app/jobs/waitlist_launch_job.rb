# frozen_string_literal: true

# Emails everyone waiting for the iPhone or Android app that it's out.
# Each person is emailed once per platform (ios_notified_at / android_notified_at),
# so running it again only reaches people who joined since.
class WaitlistLaunchJob < ApplicationJob
  queue_as :default

  def perform(platform)
    platform = platform.to_s
    raise ArgumentError, "unknown platform #{platform}" unless WaitlistMailer::STORES.key?(platform)
    return unless WaitlistMailer.live?(platform)

    column = AppWaitlistEntry::NOTIFIED_COLUMNS.fetch(platform)
    AppWaitlistEntry.waiting_for(platform).find_each do |entry|
      WaitlistMailer.with(entry: entry, platform: platform).launched.deliver_now
      entry.update_columns(column => Time.current, confirmed_at: entry.confirmed_at || Time.current)
    rescue StandardError => e
      Rails.logger.error("[waitlist] launch email to entry #{entry.id} failed: #{e.class}: #{e.message}")
    end
  end
end
