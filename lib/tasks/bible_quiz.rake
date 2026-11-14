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

  desc "Top up every theme × difficulty to the pool target, inline (e.g. bible_quiz:warm_pool[40])"
  task :warm_pool, [ :target ] => :environment do |_t, args|
    target = (args[:target] || BibleQuizQuestion::POOL_TARGET).to_i
    if Ai::Moderation::Client.stub?
      warn "AI provider not configured (stub) — nothing to generate."
      next
    end

    short = BibleQuizWarmPoolJob.short_filters(target)
    puts "#{short.size} theme × difficulty filters below #{target} trusted questions."
    total = 0
    short.each do |theme, diff|
      batches = ((target - BibleQuizQuestion.pool_size(theme: theme, difficulty: diff)) / 4.0).ceil.clamp(1, 12)
      added = BibleQuizTopUpJob.perform_now(theme, diff, batches, target)
      total += added.to_i
      puts "  #{theme.ljust(14)} #{diff.ljust(6)} +#{added} (now #{BibleQuizQuestion.pool_size(theme: theme, difficulty: diff)})"
    end
    puts "Done. Pool size: #{BibleQuizQuestion.trusted.count} trusted (+#{total} this run)."
  end

  desc "Take off-theme questions out of the quiz, checked by the AI (all themes, or e.g. bible_quiz:audit_themes[the_cross])"
  task :audit_themes, [ :theme ] => :environment do |_t, args|
    if Ai::Moderation::Client.stub?
      warn "AI provider not configured (stub) — can't check themes."
      next
    end

    themes = args[:theme].present? ? [ args[:theme].to_s ] : Ai::Bible::QuizGenerator::THEMES.keys
    retired = 0
    themes.each do |theme|
      raise "unknown theme: #{theme}" unless Ai::Bible::QuizGenerator::THEMES.key?(theme)

      off = []
      BibleQuizQuestion.trusted.where(theme: theme).find_in_batches(batch_size: Ai::Bible::QuizThemeCheck::BATCH) do |batch|
        off += Ai::Bible::QuizThemeCheck.call(theme: theme, questions: batch)
      rescue StandardError => e
        warn "  #{theme}: a batch failed: #{e.class}: #{e.message}"
      end
      # Retired the same way as two player flags (see BibleQuizQuestion.trusted).
      BibleQuizQuestion.where(id: off).update_all(flags_count: 2) if off.any?
      retired += off.size
      puts "  #{theme.ljust(14)} #{off.size} off-theme retired, #{BibleQuizQuestion.pool_size(theme: theme)} left"
    end
    puts "Done. Retired #{retired} off-theme questions. Run bible_quiz:warm_pool to refill thin themes."
  end

  desc "Check marked answers against the Bible: fix clear mistakes, retire the rest (fill_blank / reference / which_book)"
  task audit_answers: :environment do
    counts = Hash.new(0)
    BibleQuizQuestion.trusted.where(kind: BibleQuiz::AnswerCheck::CHECKED_KINDS).find_each do |q|
      result = BibleQuiz::AnswerCheck.call(kind: q.kind, choices: q.choices, correct_index: q.correct_index, reference: q.reference)
      counts[result.status] += 1
      case result.status
      when :fixed
        q.update_columns(correct_index: result.correct_index, updated_at: Time.current)
        puts "  fixed   ##{q.id} #{q.reference}: now #{q.choices[result.correct_index].inspect}"
      when :wrong
        q.update_columns(flags_count: 2, updated_at: Time.current) # retired, as by two player flags
        puts "  retired ##{q.id} #{q.reference}: no choice matches the Bible"
      end
    end
    puts "Done. ok=#{counts[:ok]} fixed=#{counts[:fixed]} retired=#{counts[:wrong]} unchecked=#{counts[:unknown]}"
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
