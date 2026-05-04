class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAILER_FROM", "noreply@faithcommunity.com") }
  layout "mailer"
end
