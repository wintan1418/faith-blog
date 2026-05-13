# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAILER_FROM", "Brethreign <noreply@brethreign.com>")

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
  config.password_length = 8..128
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
