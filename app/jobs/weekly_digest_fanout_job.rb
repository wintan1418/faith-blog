# frozen_string_literal: true

# Fans the weekly digest out across the user base. Runs once a week
# (config/recurring.yml). Each user's mailer is enqueued as a separate
# Solid Queue job so a slow / failing send for one address can't block
# the rest of the batch.
class WeeklyDigestFanoutJob < ApplicationJob
  queue_as :default

  def perform
    User.where(active: true)
        .where(email_notifications_enabled: true)
        .where.not(email: [ nil, "" ])
        .find_each(batch_size: 200) do |user|
      WeeklyDigestMailer.with(user: user).weekly_digest.deliver_later
    end
  end
end
