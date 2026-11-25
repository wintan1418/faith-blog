# frozen_string_literal: true

# A page's new logo or cover gets the same AI look as profile photos
# (AvatarModerationJob). If it's sexual, occult, gory or a scam it is taken
# down, the page's managers are told why, and it goes to the moderators' queue.
class PageImageModerationJob < ApplicationJob
  queue_as :moderation
  discard_on ActiveJob::DeserializationError

  def perform(page, name)
    name = name.to_s
    return unless %w[logo cover].include?(name)

    attachment = page.public_send(name)
    return unless attachment.attached?

    result = ImageModeration.review([ attachment.attachment ], kind: "page #{name}", context: "Page: #{page.name} (@#{page.handle})")
    return if result.nil? || (result.safe && result.severity.in?(%w[none low]))
    return unless result.severity.in?(%w[medium high]) || result.recommended_action.in?(%w[hide_pending_review block])

    AiModerationReview.from_result(reviewable: page, user: page.owner || page.created_by, result: result, status: :flagged).save!
    attachment.purge_later
    page.managers.each do |manager|
      Notification.create(user: manager, notifiable: page, notification_type: :content_removed)
    end
  rescue StandardError => e
    Rails.logger.warn("[PageImageModerationJob] skipped page #{page&.id} #{name}: #{e.class}: #{e.message}")
  end
end
