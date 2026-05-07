# frozen_string_literal: true

# Sends an admin-authored Broadcast to every eligible user. Each delivery
# is enqueued separately so a slow / bouncing single recipient can't
# block the rest of the run, and so retries happen at the per-user level.
class BroadcastFanoutJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(broadcast)
    return unless broadcast
    return if broadcast.sent? # idempotency — never double-send

    broadcast.update!(status: :sending, sent_at: Time.current)

    count = 0
    User.where(active: true)
        .where(email_notifications_enabled: true)
        .where.not(email: [ nil, "" ])
        .find_each(batch_size: 200) do |user|
      BroadcastMailer.with(broadcast: broadcast, user: user).announcement.deliver_later
      count += 1
    end

    broadcast.update!(status: :sent, recipients_count: count)
  rescue StandardError => e
    Rails.logger.error("[BroadcastFanoutJob] #{e.class}: #{e.message}")
    broadcast.update!(status: :failed) if broadcast
    raise
  end
end
