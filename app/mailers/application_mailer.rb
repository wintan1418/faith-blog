class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAILER_FROM", "Brethreign <noreply@brethreign.com>") }
  layout "mailer"
end
