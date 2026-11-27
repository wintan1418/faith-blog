# frozen_string_literal: true

# Delivers a launched FeedbackCampaign: one "We'd love your feedback" alert per
# targeted member. Alerts are written in batches (insert_all: no per-row
# callbacks, so no email and no push storm). A push goes out only when the
# admin ticked "also push", spread over a few minutes, batch by batch; an email
# (FeedbackMailer) only when they ticked "also email", spaced the same way.
#
# Runs at the campaign's start time (enqueued with wait_until). Safe to run
# twice: delivered_at is claimed first, and members who already have the
# alert are skipped.
class FeedbackCampaignDeliveryJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(campaign_id, *) { "feedback-campaign-#{campaign_id}" }, duration: 30.minutes
  discard_on ActiveJob::DeserializationError

  BATCH = 500
  # Each batch's pushes wait this much longer than the last one's.
  PUSH_SPACING = 30.seconds

  def perform(campaign_id, now: Time.current)
    campaign = FeedbackCampaign.find_by(id: campaign_id)
    return unless campaign && !campaign.draft? && !campaign.ended?

    # Scheduled for later (or the start time moved): the job enqueued for the new time does it.
    return if campaign.starts_at.present? && campaign.starts_at > now + 1.minute

    claimed = FeedbackCampaign.where(id: campaign.id, delivered_at: nil).update_all(delivered_at: now)
    return if claimed.zero?

    delivered = 0
    campaign.audience_scope(now: now).in_batches(of: BATCH).each_with_index do |users, index|
      ids = users.pluck(:id) - Notification.where(notifiable: campaign, user_id: users.select(:id)).pluck(:user_id)
      next if ids.empty?

      rows = ids.map do |user_id|
        { user_id: user_id, notifiable_type: "FeedbackCampaign", notifiable_id: campaign.id,
          notification_type: Notification.notification_types[:feedback_request], created_at: now, updated_at: now }
      end
      inserted = Notification.insert_all(rows, returning: %w[id])
      delivered += ids.size
      push(inserted.rows.flatten, wait: PUSH_SPACING * index) if campaign.also_push?
      email(campaign, ids, wait: PUSH_SPACING * index) if campaign.also_email?
    end

    campaign.update_columns(targeted_count: delivered, updated_at: Time.current)
  end

  private

  def email(campaign, user_ids, wait:)
    User.where(id: user_ids, email_notifications_enabled: true).where.not(email: [ nil, "" ]).find_each do |user|
      FeedbackMailer.with(campaign: campaign, user: user).survey.deliver_later(wait: wait)
    end
  rescue StandardError => e
    Rails.logger.warn("[feedback] email batch failed: #{e.class}: #{e.message}")
  end

  def push(notification_ids, wait:)
    return unless WebPushConfig.configured? || NativePushConfig.configured?

    jobs = Notification.where(id: notification_ids).map { |n| PushNotificationJob.new(n).set(wait: wait) }
    ActiveJob.perform_all_later(jobs)
  rescue StandardError => e
    Rails.logger.warn("[feedback] push batch failed: #{e.class}: #{e.message}")
  end
end
