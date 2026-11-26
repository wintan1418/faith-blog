# frozen_string_literal: true

module DailyBibleHelper
  # "12 brethren read today" — a count only, never who.
  def daily_bible_readers_text(count, read: false)
    others = read ? count.to_i - 1 : count.to_i
    if read
      others.positive? ? "You and #{pluralize(others, 'other brother or sister', plural: 'other brethren')} read today" : "You're the first of the brethren to read today"
    else
      count.to_i.zero? ? "Be the first of the brethren to read today" : "#{count == 1 ? '1 of the brethren' : "#{number_with_delimiter(count)} brethren"} read today"
    end
  end

  # Where "Read today's chapter" goes from elsewhere (What's new): the first
  # chapter of the member's next reading, or the feed card if that can't be worked out.
  def daily_bible_today_path
    chapter = user_signed_in? && BibleHabit.for(current_user).portion&.first
    chapter ? scripture_page_path(chapter.slug) : feed_path
  rescue StandardError
    feed_path
  end

  # The chapter a member read today, for "Share what stood out".
  def daily_bible_read_today_label(habit)
    slug = habit.user.bible_reading_days.where(read_on: habit.today).pick(:first_chapter)
    Scripture::Reference.from_slug(slug.to_s)&.to_s
  end

  def daily_bible_share_prefill(label)
    label.present? ? "What stood out to me in #{label} today: " : "What stood out to me in my Bible reading today: "
  end

  # "Share this prayer": the burden, the points with their verses and the
  # closing prayer, ready for the composer.
  def daily_bible_prayer_share_text(chapter, prayer)
    parts = [ "Praying through #{chapter} today." ]
    parts << "Today's burden: #{prayer.burden}" if prayer.burden.present?
    parts << prayer.points.map { |point| "• #{point.text} (#{point.reference})" }.join("\n") if prayer.points?
    parts << prayer.body
    parts.join("\n\n")
  end

  # Verses offered as the key verse on "Share what I read": the prayer's key
  # verses and the chapter's well-known ones first, then every verse.
  # => [[label, slug, text], …] suggested, and [[number, slug, text], …] all.
  def daily_bible_share_verses(chapter, prayer, passage)
    texts = passage.primary.to_h
    suggested = (prayer.verse_references + Scripture::Catalog.popular_in(chapter.book, chapter.chapter))
                .reject(&:range?).uniq(&:slug).select { |ref| texts.key?(ref.verse_start) }.first(4)
    all = texts.map { |number, text| [ number, Scripture::Reference.build(chapter.book, chapter.chapter, number).slug, text ] }
    [ suggested.map { |ref| [ ref.to_s, ref.slug, texts[ref.verse_start] ] }, all ]
  rescue StandardError
    [ [], [] ]
  end

  def daily_bible_streak_text(streak) = "#{streak}-day streak"

  # Reminder times on the sheet: every half hour from 5:00 to 22:00.
  def daily_bible_reminder_options(habit)
    times = (10..44).map { |half| format("%02d:%02d", half / 2, (half % 2) * 30) }
    times << habit.reminder_time_label unless times.include?(habit.reminder_time_label)
    times.sort.map { |t| [ Time.zone.parse(t).strftime("%-l:%M %P"), t ] }
  end
end
