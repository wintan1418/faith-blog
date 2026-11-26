# frozen_string_literal: true

namespace :celebrations do
  desc "Add the built-in occasions (Christmas, Easter, national days…) for the next 12 months as drafts"
  task seed_presets: :environment do
    created = Celebrations::Presets.seed!
    state = Celebration.auto_activate_presets? ? "live (auto-activate is on)" : "drafts"
    puts "Added #{created.size} occasion(s) as #{state}:"
    created.each { |c| puts "  #{c.local_starts_at.strftime('%a %-d %b %Y')}  #{c.name}  (#{c.audience_label})" }
  end
end
