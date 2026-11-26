# frozen_string_literal: true

# Sends the "you're on the list" email after someone joins the app waitlist.
# If their app is already out, that email carries the download link, so they
# also count as told about that launch.
class WaitlistConfirmationJob < ApplicationJob
  queue_as :default

  def perform(entry_id)
    entry = AppWaitlistEntry.find_by(id: entry_id)
    return unless entry && entry.confirmed_at.nil?

    WaitlistMailer.with(entry: entry).joined.deliver_now
    stamps = { confirmed_at: Time.current }
    %w[ios android].each do |p|
      next unless WaitlistMailer.live?(p) && [ p, "both" ].include?(entry.platform)

      column = AppWaitlistEntry::NOTIFIED_COLUMNS.fetch(p)
      stamps[column] = entry.public_send(column) || Time.current
    end
    entry.update_columns(stamps)
  end
end
