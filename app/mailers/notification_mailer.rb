# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def community_notification
    @notification = params.fetch(:notification)
    @user = @notification.user
    @actor = @notification.actor
    @target_url = URI.join(root_url, @notification.target_path).to_s

    mail(
      to: @user.email,
      subject: "[Brethreign] #{@notification.message}"
    )
  end
end
