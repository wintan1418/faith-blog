# frozen_string_literal: true

namespace :scripture do
  desc "Load the KJV, WEB and BSB text and the cross-references (idempotent; FORCE=1 reloads)"
  task import: :environment do
    Scripture::Importer.call(force: ENV["FORCE"] == "1")
  end

  desc "Index the Bible references in every breath (backfill for scripture pages)"
  task citations: :environment do
    count = 0
    Post.includes(:rich_text_content).find_each do |post|
      ScriptureCitation.sync(post)
      count += 1
    end
    puts "Indexed #{count} breaths; #{ScriptureCitation.count} citations."
  end

  # Writes insights for the next pages in priority order (most-searched
  # verses first, then quoted verses, then every chapter).
  #   bin/rails "scripture:insights[200]"           enqueue 200, one every PACE seconds
  #   INLINE=1 bin/rails "scripture:insights[10]"   write 10 now, in this process
  # Never goes past ScriptureInsight::CAP pages in total.
  desc "Generate AI insights for the next N scripture pages (default 100, PACE=4 seconds apart)"
  task :insights, [ :count ] => :environment do |_, args|
    if Ai::Moderation::Client.stub?
      abort "No AI key configured (the stub provider is active); nothing generated."
    end

    wanted = (args[:count] || 100).to_i
    room = ScriptureInsight::CAP - ScriptureInsight.count
    count = [ wanted, room ].min
    abort "Cap reached: #{ScriptureInsight.count}/#{ScriptureInsight::CAP} insights exist." if count <= 0

    pace = (ENV["PACE"] || 4).to_f
    done = ScriptureInsight.pluck(:slug).to_set
    slugs = Scripture::Catalog.queue.map(&:slug).reject { |slug| done.include?(slug) }.first(count)

    if ENV["INLINE"] == "1"
      slugs.each_with_index do |slug, i|
        ScriptureInsightJob.perform_now(slug)
        puts "  [#{i + 1}/#{slugs.size}] #{slug} — #{ScriptureInsight.exists?(slug: slug) ? 'ok' : 'skipped/failed'}"
        sleep pace if i < slugs.size - 1
      end
    else
      slugs.each_with_index { |slug, i| ScriptureInsightJob.set(wait: (i * pace).seconds).perform_later(slug) }
      puts "Enqueued #{slugs.size} insights, one every #{pace}s (#{ScriptureInsight.count}/#{ScriptureInsight::CAP} written so far)."
    end
  end
end
