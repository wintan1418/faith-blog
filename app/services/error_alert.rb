# frozen_string_literal: true

# Tells the admins the moment something breaks: a push to their phones and an
# email, at most once per problem every 15 minutes (with how many times it
# happened meanwhile). Used for page crashes (see config/initializers/
# error_alerts.rb) and the site health check (SiteHealthCheck).
module ErrorAlert
  QUIET_FOR = 15.minutes

  module_function

  # key: what makes two reports "the same problem" (error class + where).
  def notify(key:, title:, detail:)
    digest = Digest::SHA256.hexdigest(key.to_s)[0, 16]
    count_key = "error_alert:count:#{digest}"
    count = Rails.cache.increment(count_key, 1, expires_in: 1.day) || 1
    # First report in the window sends; the rest are counted for the next one.
    return unless Rails.cache.write("error_alert:sent:#{digest}", true, unless_exist: true, expires_in: QUIET_FOR)

    Rails.cache.delete(count_key)
    ErrorAlertJob.perform_later(title.to_s.truncate(120), detail.to_s.truncate(4_000), count.to_i)
  rescue StandardError => e
    Rails.logger.error("[ErrorAlert] could not raise the alert: #{e.class}: #{e.message}")
  end

  def recipients
    User.where(role: %i[admin super_admin]).where.not(email: SiteHealthCheck::EMAIL)
  end
end
