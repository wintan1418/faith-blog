# frozen_string_literal: true

module AccountSecurityHelper
  VERIFY_BANNER_HIDDEN_ON = %w[email_verifications settings/email_changes settings/securities settings/two_factors onboarding].freeze

  # "Verify your email" banner: signed-in members who haven't verified yet,
  # except on the verification screens themselves and until "Not now" this week.
  def show_verify_email_banner?
    return false unless user_signed_in?
    return false if current_user.email_verified? || current_user.site_monitor?
    return false if controller_path.in?(VERIFY_BANNER_HIDDEN_ON) || content_for?(:bare_page)

    !current_user.card_dismissed?(verify_email_banner_key)
  end

  def verify_email_banner_key = "verify-email-w#{Date.current.cweek}"
end
