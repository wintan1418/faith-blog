# frozen_string_literal: true

module Ai
  module Office
    module Tools
      # The Admin dashboard's numbers, for questions like "how many people
      # joined this week?". Read-only.
      class SiteStats < Base
        def self.definition
          {
            name: "site_stats",
            description: "Live Brethreign numbers for the last 7, 30 or 90 days (Lagos time) compared with the period before: visitors, new and active members, breaths, prayers, conversations, sign-up funnel, traffic sources, countries, devices, top rooms and the safety queue.",
            parameters: {
              type: "object",
              properties: { days: { type: "integer", description: "7, 30 or 90. Default 7." } }
            }
          }
        end

        def call
          stats = AdminDashboardStats.new(input["days"].presence || 7)
          result = {
            "period" => "last #{stats.days} days (#{stats.from.to_date} to #{stats.to.to_date}, Lagos time)",
            "members_total" => User.count
          }
          section(result, "headline") do
            stats.kpis.map { |k| { "label" => k.label, "value" => k.value, "previous_period" => k.previous, "change_percent" => k.change, "note" => k.note } }
          end
          section(result, "signup_funnel") { stats.funnel.to_h }
          section(result, "page_views") { stats.page_views }
          section(result, "traffic_sources") { stats.sources.first(6).to_h }
          section(result, "countries") { stats.countries.first(6).to_h { |code, n| [ AdminDashboardStats.country_label(code), n ] } }
          section(result, "devices") { stats.devices.to_h }
          section(result, "top_rooms") { stats.top_rooms.to_h { |room, n| [ room.name, n ] } }
          section(result, "android_app_users") { stats.app_users }
          section(result, "safety_queue") { stats.safety.to_h { |label, n, _| [ label, n ] } }
          Outcome.new(result: result)
        end

        private

        # One broken query shouldn't hide every other number.
        def section(result, key)
          result[key] = yield
        rescue StandardError => e
          Rails.logger.warn("[Office] site_stats #{key} failed: #{e.class}: #{e.message}")
          result[key] = "unavailable"
        end
      end
    end
  end
end
