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
end
