# frozen_string_literal: true

namespace :bible_quiz do
  desc "Generate N batches of Bible quiz questions (each batch = 5) via AI and store them"
  task :seed, [ :batches ] => :environment do |_t, args|
    batches = (args[:batches] || 10).to_i
    puts "Generating #{batches} batches (~#{batches * 5} questions, dedupes on prompt)…"

    total_inserted = 0
    batches.times do |i|
      begin
        qs = Ai::Bible::QuizGenerator.call
        inserted = BibleQuizQuestion.import_from_generator!(qs)
        total_inserted += inserted
        print "  batch #{i + 1}/#{batches}: +#{inserted} (#{BibleQuizQuestion.count} total)\r"
        $stdout.flush
        sleep 0.5  # gentle throttle
      rescue StandardError => e
        warn "  batch #{i + 1} failed: #{e.class}: #{e.message}"
      end
    end
    puts ""
    puts "Done. Pool size: #{BibleQuizQuestion.count} (+#{total_inserted} added this run)."
  end

  desc "Show pool stats"
  task stats: :environment do
    by_kind = BibleQuizQuestion.group(:kind).count
    puts "Total: #{BibleQuizQuestion.count}"
    by_kind.each { |k, n| puts "  #{k.to_s.ljust(15)} #{n}" }
  end
end
