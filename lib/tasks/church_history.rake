# frozen_string_literal: true

namespace :church_history do
  desc "Seed the 60 curated church-history figures (idempotent — safe to re-run)"
  task seed: :environment do
    load Rails.root.join("db/seeds/church_history_figures.rb")
  end

  desc "Regenerate (or fill) AI bios for any figure that doesn't have one yet"
  task fill_bios: :environment do
    pending = ChurchHistoryFigure.where(bio: [ nil, "" ])
    puts "Generating bios for #{pending.count} figures…"
    pending.find_each.with_index do |fig, i|
      begin
        result = Ai::Christian::FigureBio.call(figure: fig)
        fig.update!(
          bio: result[:bio],
          featured_quote: fig.featured_quote.presence || result[:quote],
          bio_generated_at: Time.current
        )
        puts "  [#{i + 1}] #{fig.name} — ok"
        sleep 0.4
      rescue StandardError => e
        warn "  [#{i + 1}] #{fig.name} — FAILED: #{e.class}: #{e.message}"
      end
    end
  end

  desc "Regenerate the per-era chronicle narratives"
  task fill_chronicles: :environment do
    ChurchHistoryFigure.eras.keys.each do |era|
      begin
        text = Ai::Christian::EraChronicle.call(era: era)
        row  = ChurchHistoryEra.find_or_initialize_by(slug: era)
        row.summary = text
        row.generated_at = Time.current
        row.save!
        puts "  #{era} — ok"
        sleep 0.4
      rescue StandardError => e
        warn "  #{era} — FAILED: #{e.class}: #{e.message}"
      end
    end
  end
end
