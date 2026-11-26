# frozen_string_literal: true

namespace :bible_today do
  # Writes the after-reading prayer burden for the next chapters that have
  # none, or only an older version (ChapterPrayer::VERSION), in reading-plan
  # order (the default plan first: John, the New Testament, then the Old), so
  # the chapters members reach first are ready first. Members still see the
  # older prayer (or the fallback) until each new one is written.
  #   bin/rails "bible_today:prayers[200]"           enqueue 200, one every PACE seconds
  #   INLINE=1 bin/rails "bible_today:prayers[10]"   write 10 now, in this process
  #   bin/rails bible_today:prayers_status           how many are current
  # Never goes past ChapterPrayer::CAP (one per chapter).
  desc "Write AI prayer burdens for the next N Bible chapters missing or outdated (default 100, PACE=4 seconds apart)"
  task :prayers, [ :count ] => :environment do |_, args|
    abort "No AI key configured (the stub provider is active); nothing generated." if Ai::Moderation::Client.stub?

    wanted = (args[:count] || 100).to_i
    done = ChapterPrayer.where(version: ChapterPrayer::VERSION..).pluck(:slug).to_set
    slugs = DailyBible::Plan.default.portions.flat_map(&:chapters).map(&:slug).uniq.reject { |slug| done.include?(slug) }.first(wanted)
    abort "Every chapter already has a current prayer burden (#{done.size})." if slugs.empty?

    pace = (ENV["PACE"] || 4).to_f
    if ENV["INLINE"] == "1"
      slugs.each_with_index do |slug, i|
        ChapterPrayerJob.perform_now(slug)
        ok = ChapterPrayer.where(slug: slug, version: ChapterPrayer::VERSION..).exists?
        puts "  [#{i + 1}/#{slugs.size}] #{slug} — #{ok ? 'ok' : 'skipped/failed'}"
        sleep pace if i < slugs.size - 1
      end
    else
      slugs.each_with_index { |slug, i| ChapterPrayerJob.set(wait: (i * pace).seconds).perform_later(slug) }
      puts "Enqueued #{slugs.size} chapter prayers, one every #{pace}s (#{done.size}/#{ChapterPrayer::CAP} current so far)."
    end
  end

  desc "How many chapters have a current prayer burden, an outdated one, or none"
  task prayers_status: :environment do
    current = ChapterPrayer.where(version: ChapterPrayer::VERSION..).count
    outdated = ChapterPrayer.outdated.count
    puts "Chapter prayers v#{ChapterPrayer::VERSION}: #{current} current, #{outdated} outdated (shown until rewritten), " \
         "#{ChapterPrayer::CAP - current - outdated} not written yet."
  end
end
