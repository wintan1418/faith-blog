# frozen_string_literal: true

namespace :cities do
  desc "Download GeoNames cities and load/refresh the cities table (DATASET=cities5000|cities15000|cities1000; idempotent)"
  task import: :environment do
    GeonamesImport.new(dataset: ENV.fetch("DATASET", "cities5000")).call
  end

  desc "Load the small built-in list of cities (development/test; no download)"
  task sample: :environment do
    puts "Cities: #{GeonamesImport.load_sample!} sample cities loaded."
  end

  desc "Match members' free-text locations to cities. Dry run unless APPLY=1"
  task backfill: :environment do
    CityBackfill.new(apply: ENV["APPLY"] == "1").call
  end

  desc "Members with 3+ city changes in the last 30 days (possible town scanning)"
  task movers: :environment do
    counts = CityChange.frequent_movers
    if counts.empty?
      puts "Nobody has changed city #{CityChange::WATCH_AT}+ times in the last #{CityChange::WINDOW.in_days.to_i} days."
      next
    end

    users = User.where(id: counts.keys).index_by(&:id)
    counts.each do |user_id, n|
      changes = CityChange.recent.where(user_id: user_id).includes(:to_city).order(:created_at)
      trail = changes.map { |c| c.to_city&.name || "(cleared)" }.join(" -> ")
      puts format("%-24s %2d changes  %s", "@#{users[user_id]&.username || user_id}", n, trail)
    end
  end
end
