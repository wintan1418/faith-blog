# frozen_string_literal: true

# Site analytics for Admin → Dashboard: visits, page views, where people come from.
# Privacy: no cookies (visitors are recognised by a hash of masked IP + browser),
# IPs are masked, bots are skipped, and rows older than 13 months are deleted.
class Ahoy::Store < Ahoy::DatabaseStore
  def track_visit(data)
    data[:country] = request&.headers&.[]("CF-IPCountry").presence&.then { |c| c unless c == "XX" || c == "T1" }
    version = request&.user_agent.to_s[%r{Brethreign/(\d+(?:\.\d+)*)}, 1]
    native = request&.user_agent.to_s.include?("Hotwire Native")
    data[:platform] = native ? (request.user_agent.include?("Android") ? "android_app" : "ios_app") : "web"
    data[:app_version] = version if native
    super(data)
  rescue StandardError => e
    Rails.logger.warn("[ahoy] #{e.class}: #{e.message}")
  end

  # Analytics must never break a page.
  def track_event(data)
    super
  rescue StandardError => e
    Rails.logger.warn("[ahoy] #{e.class}: #{e.message}")
  end
end

Ahoy.api = false
Ahoy.geocode = false
Ahoy.cookies = :none
Ahoy.mask_ips = true
Ahoy.visit_duration = 30.minutes
Ahoy.server_side_visits = :when_needed
Ahoy.job_queue = :default
