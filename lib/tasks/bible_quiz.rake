# frozen_string_literal: true

namespace :bible_quiz do
  desc "Seed N batches across all formation themes × difficulties (e.g. bible_quiz:seed_all[3])"
  task :seed_all, [ :batches_per_theme ] => :environment do |_t, args|
    per = (args[:batches_per_theme] || 3).to_i
    themes = Ai::Bible::QuizGenerator::THEMES.keys - [ "bible_history" ]
    difficulties = Ai::Bible::QuizGenerator::DIFFICULTIES

    puts "Generating #{per} batches per theme × difficulty (#{themes.size} themes × #{difficulties.size} = #{themes.size * difficulties.size * per} batches)…"

    inserted = 0
    themes.each do |theme|
      difficulties.each do |diff|
        per.times do |i|
          begin
            qs = Ai::Bible::QuizGenerator.call(theme: theme, difficulty: diff)
            added = BibleQuizQuestion.import_from_generator!(qs)
            inserted += added
            print "  #{theme.ljust(14)} #{diff.ljust(6)} ##{i + 1}/#{per}: +#{added} (#{BibleQuizQuestion.count} total)\r"
            $stdout.flush
            sleep 0.4
          rescue StandardError => e
            warn "\n  #{theme} #{diff} ##{i + 1} failed: #{e.class}: #{e.message}"
          end
        end
        puts ""
      end
    end
    puts "Done. Pool size: #{BibleQuizQuestion.count} (+#{inserted} this run)."
  end

  desc "Seed N batches for ONE theme (and optional difficulty), e.g. bible_quiz:seed_theme[salvation,easy,10]"
  task :seed_theme, [ :theme, :difficulty, :batches ] => :environment do |_t, args|
    theme = args[:theme].to_s
    diff  = args[:difficulty].to_s.presence
    batches = (args[:batches] || 10).to_i
    raise "unknown theme: #{theme}" unless Ai::Bible::QuizGenerator::THEMES.key?(theme)

    inserted = 0
    batches.times do |i|
      begin
        qs = Ai::Bible::QuizGenerator.call(theme: theme, difficulty: diff)
        added = BibleQuizQuestion.import_from_generator!(qs)
        inserted += added
        print "  #{theme} #{diff || "mixed"} ##{i + 1}/#{batches}: +#{added} (#{BibleQuizQuestion.where(theme: theme).count} on theme)\r"
        $stdout.flush
        sleep 0.4
      rescue StandardError => e
        warn "\n  #{theme} ##{i + 1} failed: #{e.class}: #{e.message}"
      end
    end
    puts "\nDone. Theme '#{theme}' now has #{BibleQuizQuestion.where(theme: theme).count} questions (+#{inserted} this run)."
  end

  desc "Show pool stats by theme / difficulty"
  task stats: :environment do
    puts "Total: #{BibleQuizQuestion.count}"
    puts ""
    puts "By theme:"
    BibleQuizQuestion.group(:theme).count.sort_by { |_, n| -n }.each do |t, n|
      puts "  #{t.to_s.ljust(18)} #{n}"
    end
    puts ""
    puts "By difficulty:"
    BibleQuizQuestion.group(:difficulty).count.each do |d, n|
      puts "  #{d.to_s.ljust(8)} #{n}"
    end
  end

  # Backwards-compat: old `seed[N]` keeps working (untouched themes).
  desc "Seed N batches (back-compat — themes/difficulties randomly chosen)"
  task :seed, [ :batches ] => :environment do |_t, args|
    batches = (args[:batches] || 10).to_i
    inserted = 0
    batches.times do |i|
      qs = Ai::Bible::QuizGenerator.call
      inserted += BibleQuizQuestion.import_from_generator!(qs)
      print "  ##{i + 1}/#{batches} (#{BibleQuizQuestion.count} total)\r"
      $stdout.flush
      sleep 0.4
    rescue StandardError => e
      warn "\n  ##{i + 1} failed: #{e.class}: #{e.message}"
    end
    puts "\nDone. (+#{inserted} this run)"
  end
end
