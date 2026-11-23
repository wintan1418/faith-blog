# frozen_string_literal: true

namespace :seeds do
  desc "Award seeds for activity from before Seeds existed (same rules and daily caps; safe to re-run)"
  task backfill: :environment do
    Seeds::Backfill.new.run
  end
end
