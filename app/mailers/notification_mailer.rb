# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def community_notification
    @notification = params.fetch(:notification)
    @user = @notification.user
    @actor = @notification.actor
    # Link through the visit redirector, NOT the target's URL directly: a
    # baked post URL 404s forever once the post is deleted or re-slugged,
    # while /visit recomputes the destination when the reader clicks.
    @target_url = visit_notification_url(@notification)

    mail(
      to: @user.email,
      subject: "[Brethreign] #{@notification.message}"
    )
  end
end
