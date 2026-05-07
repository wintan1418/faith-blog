# frozen_string_literal: true

class BroadcastMailer < ApplicationMailer
  def announcement
    @broadcast = params.fetch(:broadcast)
    @user      = params.fetch(:user)
    return if @user.email_notifications_enabled == false
    return if @user.email.blank?

    @host = default_url_host
    @feed_url = Rails.application.routes.url_helpers.feed_url(host: @host)
    @unsubscribe_url = build_unsubscribe_url(@user)

    mail to: @user.email,
         subject: @broadcast.subject
  end

  private

  def default_url_host
    Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
  end

  def build_unsubscribe_url(user)
    token = Rails.application.message_verifier(:weekly_digest_unsubscribe).generate(user.id, expires_in: 90.days)
    Rails.application.routes.url_helpers.email_unsubscribes_weekly_digest_url(token: token, host: @host)
  end
end
