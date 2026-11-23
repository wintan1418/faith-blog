# frozen_string_literal: true

require "net/http"

# Keeps scripted sign-ups out without bothering real people:
#   * a honeypot field humans never see (bots fill every input),
#   * a signed "form shown at" stamp — a human takes more than a few seconds
#     to fill the form; a bot posts instantly (or without loading the form),
#   * Cloudflare Turnstile, when TURNSTILE_SITE_KEY + TURNSTILE_SECRET_KEY
#     are set (invisible/managed challenge, verified server-side).
# Blocked attempts are counted per day for the admins' morning summary
# (DailySummaryJob); they never send an email on their own.
module SignupGuard
  HONEYPOT_PARAM = :hp_website
  TOKEN_PARAM    = :form_token
  MIN_FILL_TIME  = 3.seconds
  TOKEN_TTL      = 1.day
  REASONS = %w[honeypot missing_or_expired_token too_fast turnstile].freeze
  TURNSTILE_VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  module_function

  def form_token(issued_at: Time.current)
    verifier.generate(issued_at.to_i, expires_in: TOKEN_TTL, purpose: :signup_form)
  end

  # Returns nil when the request looks human, else a short reason (for logs).
  # turnstile: false for light forms that don't show the widget (the app
  # waitlist); they lean on the honeypot, fill time and a rate limit.
  def bot_reason(params, remote_ip:, turnstile: true)
    return "honeypot" if params[HONEYPOT_PARAM].present?

    issued = verifier.verified(params[TOKEN_PARAM].to_s, purpose: :signup_form)
    return "missing_or_expired_token" unless issued.is_a?(Integer)
    return "too_fast" if Time.current.to_i - issued < MIN_FILL_TIME.to_i

    return "turnstile" if turnstile && turnstile_enabled? && !turnstile_passed?(params["cf-turnstile-response"], remote_ip)

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

  # Bots are counted for the morning summary (DailySummaryJob), not emailed one by one.
  def record_block!(reason, where:, remote_ip:, email:)
    domain = email.to_s.split("@", 2)[1]
    Rails.logger.warn("[SignupGuard] blocked #{where} (#{reason}) ip=#{remote_ip} email_domain=#{domain}")
    store = AuthThrottleStore.store
    day = "signup_guard:day:#{Date.current.iso8601}"
    [ "total", "reason:#{reason}", "where:#{where}" ].each do |part|
      store.increment("#{day}:#{part}", 1, expires_in: 3.days) || store.write("#{day}:#{part}", 1, expires_in: 3.days)
    end
    store.write("#{day}:latest", "#{where}, #{reason}, IP #{remote_ip}, #{domain}", expires_in: 3.days)
  rescue StandardError => e
    Rails.logger.warn("[SignupGuard] couldn't count the block: #{e.class}: #{e.message}")
  end

  # What the bot guard stopped on one day: { total:, reasons: {..}, places: {..}, latest: }.
  def blocked_on(date)
    store = AuthThrottleStore.store
    day = "signup_guard:day:#{date.iso8601}"
    read = ->(part) { store.read("#{day}:#{part}").to_i }
    {
      total: read.call("total"),
      reasons: REASONS.index_with { |r| read.call("reason:#{r}") }.select { |_, n| n.positive? },
      places: [ "sign-up", "password reset", "app waitlist" ].index_with { |w| read.call("where:#{w}") }.select { |_, n| n.positive? },
      latest: store.read("#{day}:latest")
    }
  end

  def verifier
    Rails.application.message_verifier("signup_guard")
  end
end
