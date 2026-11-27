# frozen_string_literal: true

# "We'd love your feedback": the email side of a FeedbackCampaign launched with
# "also email". One button straight to the survey page.
class FeedbackMailer < ApplicationMailer
  def survey
    @campaign = params.fetch(:campaign)
    @user     = params.fetch(:user)
    return if @user.email.blank? || @user.email_notifications_enabled == false
    return if @campaign.ended? || @campaign.responses.submitted.exists?(user_id: @user.id)

    @host = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
    @survey_url = Rails.application.routes.url_helpers.feedback_survey_url(@campaign, host: @host)
    @settings_url = "https://#{@host}/settings/notifications/edit"
    token = Rails.application.message_verifier(:weekly_digest_unsubscribe).generate(@user.id, expires_in: 90.days)
    @unsubscribe_url = Rails.application.routes.url_helpers.email_unsubscribes_weekly_digest_url(token: token, host: @host)

    mail to: @user.email, subject: "#{@campaign.title} (#{@campaign.duration_label})"
  end
end
