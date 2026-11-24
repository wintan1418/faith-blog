# frozen_string_literal: true

namespace :series do
  # Groups existing breaths into series. A DRY RUN by default: it only prints
  # what it would do. Two sources, in this order:
  #
  #   1. config/series_mapping.yml: series checked by hand (post ids and part
  #      numbers), for what titles can't show.
  #   2. Title detection for every other breath: same author, same base title
  #      with a part marker ("(1)", "(#2)", "(2/7)", "Part 3", "Day 1", even in
  #      Unicode bold; an untitled breath by the first line of its words).
  #
  #   bin/rails series:suggest                  # print the plan
  #   APPLY=1 bin/rails series:suggest          # create the series and add the parts
  #   ONLY_MAPPING=1 …                          # skip title detection
  #   MAPPING=path/to.yml … / MAPPING=none      # another mapping file, or none
  #   SINGLES=1 …                               # also make one-part series from titles
  #   AUTHOR=username …                         # title detection for one writer only
  #
  # The writer's own part numbers are kept, gaps included. Breaths already in
  # a series stay where they are. Post titles are never changed.
  desc "Suggest (and with APPLY=1 create) series from the hand-checked mapping and breath titles"
  task suggest: :environment do
    apply = ENV["APPLY"] == "1"
    puts apply ? "APPLYING series" : "DRY RUN: nothing is written (APPLY=1 to create)"

    mapping_path = ENV.fetch("MAPPING", SeriesMapping::DEFAULT_PATH.to_s)
    entries = mapping_path == "none" || !File.exist?(mapping_path) ? [] : SeriesMapping.load(mapping_path)
    created = joined = 0

    if entries.any?
      puts "", "== From #{mapping_path.delete_prefix("#{Rails.root}/")} (#{entries.size} entries) =="
      entries.each do |entry|
        puts entry.report_lines
        next unless apply

        made, count = entry.apply!
        created += 1 if made
        joined += count
      end
    end

    unless ENV["ONLY_MAPPING"] == "1"
      scope = Post.all
      if ENV["AUTHOR"].present?
        user = User.where("LOWER(username) = ?", ENV["AUTHOR"].downcase).first or abort("No member @#{ENV['AUTHOR']}")
        scope = scope.where(user: user)
      end
      groups = SeriesSuggestions.groups(scope, singles: true, exclude_ids: entries.flat_map(&:post_ids))
      runs, singles = groups.partition { |group| group.posts.size > 1 }
      runs += singles if ENV["SINGLES"] == "1"

      puts "", "== From titles (breaths not in the mapping) =="
      puts "  (none)" if runs.empty?
      runs.each do |group|
        existing = group.user.series.find { |s| SeriesTitle.key_for(s.title) == group.key }
        taken = existing ? existing.posts.pluck(:series_position).compact : []
        plan = group.posts.map do |post|
          number = SeriesTitle.parse(SeriesTitle.effective_title(post))&.part
          number = taken.max.to_i + 1 if post.series_id.nil? && (number.nil? || taken.include?(number))
          taken << number if post.series_id.nil?
          [ post, number ]
        end
        numbers = plan.map(&:last).compact
        gaps = numbers.any? ? (1..numbers.max).to_a - numbers : []
        puts "@#{group.user.username} · \"#{group.title}\" (#{existing ? 'existing series' : 'new series'}, " \
             "#{group.posts.size} parts#{", missing part #{gaps.join(', ')}" if gaps.any?})"
        plan.each do |post, number|
          note = if post.series_id && post.series_id != existing&.id then "  [already in another series, skipped]"
          elsif post.series_id then "  [already in it]"
          elsif !post.series_listable? then "  [joins; readers won't see it: #{post.prayer? ? 'prayer request' : post.status}]"
          end
          puts format("  Part %-2s #%-5d %s%s", number || "?", post.id, SeriesTitle.effective_title(post).to_s.truncate(80), note)
        end
        next unless apply

        Series.transaction do
          series = existing || group.user.series.create!(title: group.title)
          created += 1 unless existing
          plan.each do |post, number|
            next if post.series_id

            post.update_columns(series_id: series.id, series_position: number)
            joined += 1
          end
        end
      end

      if singles.any? && ENV["SINGLES"] != "1"
        puts "", "Only one part so far (reported, not created; SINGLES=1 to include):"
        singles.each do |group|
          post = group.posts.first
          puts format("  @%s · \"%s\"  #%d %s", group.user.username, group.title, post.id, SeriesTitle.effective_title(post).to_s.truncate(80))
        end
      end
    end

    puts ""
    puts apply ? "Done: #{created} series created, #{joined} breaths added." : "Dry run only. Run with APPLY=1 to write."
  end
end
