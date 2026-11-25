# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAILER_FROM", "Brethreign <noreply@brethreign.com>")

  # Devise's emails (reset password, unlock) use the branded mailer layout.
  config.parent_mailer = "ApplicationMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth ]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  # Stay signed in for 6 months (LinkedIn / X feel). The remember-me cookie
  # is auto-set on every sign-in (form defaults remember_me to checked);
  # extend_remember_period bumps the cookie expiry on each visit so an
  # active user effectively never gets signed out.
  config.remember_for = 6.months
  config.extend_remember_period = true
  # New passwords only — Devise validates length when a password is set, so
  # existing (shorter) passwords keep working until they're changed.
  config.password_length = 10..128

  # Never reveal whether an email has an account (sign-in, password reset,
  # unlock all answer the same way either way).
  config.paranoid = true

  # :lockable — after 10 wrong passwords in a row the account locks; an
  # unlock link is emailed and it also unlocks by itself after an hour.
  config.lock_strategy = :failed_attempts
  config.unlock_keys = [ :email ]
  config.unlock_strategy = :both
  config.maximum_attempts = 10
  config.unlock_in = 1.hour
  config.last_attempt_warning = true

  # The OLD address is told when the email changes, and the member when their
  # password changes, so a hijacked session can't quietly take the account.
  # AccountSecurityMailer sends those (branded, with "Wasn't you?" help), so
  # Devise's own plain versions are off.
  config.send_email_changed_notification = false
  config.send_password_change_notification = false
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  if ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
    config.omniauth :google_oauth2,
                    ENV.fetch("GOOGLE_CLIENT_ID"),
                    ENV.fetch("GOOGLE_CLIENT_SECRET"),
                    scope: "email,profile",
                    prompt: "select_account"
  end

  # Turbo compatibility
  config.navigational_formats = [ "*/*", :html, :turbo_stream ]
end
