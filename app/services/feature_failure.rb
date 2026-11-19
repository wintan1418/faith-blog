# frozen_string_literal: true

# A feature can fail without crashing the page (it shows the member a polite
# error instead), so crash alerts never fire. Count those failures and alert
# the admins (ErrorAlert) once a feature fails several times within an hour.
module FeatureFailure
  THRESHOLD = 3
  WINDOW = 1.hour

  module_function

  def record(feature, reason)
    key = "feature_failure:#{feature}"
    count = Rails.cache.increment(key, 1, expires_in: WINDOW) || 1
    return if count < THRESHOLD

    ErrorAlert.notify(
      key: "feature|#{feature}",
      title: "#{feature.to_s.humanize} keeps failing (#{count} in the last hour)",
      detail: "Members are seeing an error message, not a crash.\nLatest: #{reason.to_s.truncate(400)}\nTime: #{Time.current.utc.iso8601}"
    )
  rescue StandardError => e
    Rails.logger.warn("[FeatureFailure] #{e.class}: #{e.message}")
  end
end
