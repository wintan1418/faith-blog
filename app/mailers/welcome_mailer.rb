# frozen_string_literal: true

class WelcomeMailer < ApplicationMailer
  def welcome
    @user = params.fetch(:user)
    @existing = params.fetch(:existing, false)
    @host = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
    @feed_url = Rails.application.routes.url_helpers.feed_url(host: @host)
    token = Rails.application.message_verifier(:weekly_digest_unsubscribe).generate(@user.id, expires_in: 90.days)
    @unsubscribe_url = Rails.application.routes.url_helpers.email_unsubscribes_weekly_digest_url(token: token, host: @host)

    mail to: @user.email, subject: WelcomeNote.subject(@user)
  end
end
