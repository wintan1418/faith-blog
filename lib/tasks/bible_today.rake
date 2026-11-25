# frozen_string_literal: true

namespace :bible_today do
  # Writes the after-reading prayer for the next chapters that have none, in
  # reading-plan order (the default plan first: John, the New Testament, then
  # the Old), so the chapters members reach first are ready first.
  #   bin/rails "bible_today:prayers[200]"           enqueue 200, one every PACE seconds
  #   INLINE=1 bin/rails "bible_today:prayers[10]"   write 10 now, in this process
  # Never goes past ChapterPrayer::CAP (one per chapter).
  desc "Generate AI prayers for the next N Bible chapters (default 100, PACE=4 seconds apart)"
  task :prayers, [ :count ] => :environment do |_, args|
    abort "No AI key configured (the stub provider is active); nothing generated." if Ai::Moderation::Client.stub?

    wanted = (args[:count] || 100).to_i
    done = ChapterPrayer.pluck(:slug).to_set
    slugs = DailyBible::Plan.default.portions.flat_map(&:chapters).map(&:slug).uniq.reject { |slug| done.include?(slug) }.first(wanted)
    abort "Every chapter already has a prayer (#{done.size})." if slugs.empty?

    pace = (ENV["PACE"] || 4).to_f
    if ENV["INLINE"] == "1"
      slugs.each_with_index do |slug, i|
        ChapterPrayerJob.perform_now(slug)
        puts "  [#{i + 1}/#{slugs.size}] #{slug} — #{ChapterPrayer.exists?(slug: slug) ? 'ok' : 'skipped/failed'}"
        sleep pace if i < slugs.size - 1
      end
    else
      slugs.each_with_index { |slug, i| ChapterPrayerJob.set(wait: (i * pace).seconds).perform_later(slug) }
      puts "Enqueued #{slugs.size} chapter prayers, one every #{pace}s (#{done.size}/#{ChapterPrayer::CAP} written so far)."
    end
  end
end
