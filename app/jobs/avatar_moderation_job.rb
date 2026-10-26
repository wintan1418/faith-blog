# frozen_string_literal: true

# A new profile photo gets the same AI look as post photos. If it's sexual,
# occult, gory or a scam, it's taken down, the person is told why, and it goes
# to the moderators' queue.
class AvatarModerationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(profile)
    return unless profile.avatar.attached?

    result = ImageModeration.review([ profile.avatar.attachment ], kind: "profile photo")
    return if result.nil? || (result.safe && result.severity.in?(%w[none low]))
    return unless result.severity.in?(%w[medium high]) || result.recommended_action.in?(%w[hide_pending_review block])

    AiModerationReview.from_result(reviewable: profile, user: profile.user, result: result, status: :flagged).save!
    profile.avatar.purge_later
    Notification.create(user: profile.user, notifiable: profile, notification_type: :content_removed)
  rescue StandardError => e
    Rails.logger.warn("[AvatarModerationJob] skipped profile #{profile&.id}: #{e.class}: #{e.message}")
  end
end
