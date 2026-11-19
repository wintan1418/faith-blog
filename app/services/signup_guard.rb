# frozen_string_literal: true

require "net/http"

# Keeps scripted sign-ups out without bothering real people:
#   * a honeypot field humans never see (bots fill every input),
#   * a signed "form shown at" stamp — a human takes more than a few seconds
#     to fill the form; a bot posts instantly (or without loading the form),
#   * Cloudflare Turnstile, when TURNSTILE_SITE_KEY + TURNSTILE_SECRET_KEY
#     are set (invisible/managed challenge, verified server-side).
# Blocked attempts are counted; more than ALERT_THRESHOLD in an hour raises an
# admin alert so an attack is visible.
module SignupGuard
  HONEYPOT_PARAM = :hp_website
  TOKEN_PARAM    = :form_token
  MIN_FILL_TIME  = 3.seconds
  TOKEN_TTL      = 1.day
  ALERT_THRESHOLD = 5
  TURNSTILE_VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  module_function

  def form_token(issued_at: Time.current)
    verifier.generate(issued_at.to_i, expires_in: TOKEN_TTL, purpose: :signup_form)
  end

  # Returns nil when the request looks human, else a short reason (for logs).
  def bot_reason(params, remote_ip:)
    return "honeypot" if params[HONEYPOT_PARAM].present?

    issued = verifier.verified(params[TOKEN_PARAM].to_s, purpose: :signup_form)
    return "missing_or_expired_token" unless issued.is_a?(Integer)
    return "too_fast" if Time.current.to_i - issued < MIN_FILL_TIME.to_i

    return "turnstile" if turnstile_enabled? && !turnstile_passed?(params["cf-turnstile-response"], remote_ip)

    nil
  end

  def turnstile_enabled?
    turnstile_site_key.present? && turnstile_secret_key.present?
  end

  def turnstile_site_key = ENV["TURNSTILE_SITE_KEY"].presence
  def turnstile_secret_key = ENV["TURNSTILE_SECRET_KEY"].presence

  def turnstile_passed?(token, remote_ip)
    return false if token.blank?

    response = Net::HTTP.post_form(TURNSTILE_VERIFY_URL,
                                   "secret" => turnstile_secret_key, "response" => token.to_s, "remoteip" => remote_ip.to_s)
    JSON.parse(response.body)["success"] == true
  rescue StandardError => e
    # Cloudflare unreachable: don't lock real people out — the honeypot, fill
    # time and rate limits still apply.
    Rails.logger.warn("[SignupGuard] Turnstile verify failed: #{e.class}: #{e.message}")
    true
  end

  def record_block!(reason, where:, remote_ip:, email:)
    Rails.logger.warn("[SignupGuard] blocked #{where} (#{reason}) ip=#{remote_ip} email_domain=#{email.to_s.split('@', 2)[1]}")
    key = "signup_guard:blocked:#{Time.current.strftime('%Y%m%d%H')}"
    count = AuthThrottleStore.store.increment(key, 1, expires_in: 2.hours) || 1
    return unless count > ALERT_THRESHOLD

    ErrorAlert.notify(
      key: "signup_guard:bot_signups",
      title: "Bot sign-ups being blocked (#{count} this hour)",
      detail: "#{count} sign-up / password-reset attempts were blocked as bots this hour. " \
              "Latest: #{where}, reason #{reason}, IP #{remote_ip}, email domain #{email.to_s.split('@', 2)[1]}. " \
              "Nothing to do unless real people report they can't join."
    )
  end

  def verifier
    Rails.application.message_verifier("signup_guard")
  end
end
