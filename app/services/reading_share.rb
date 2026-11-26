# frozen_string_literal: true

# "Read your Bible, pray every day" shared to the feed: the data a reading
# card carries (posts.reading_share), built on the server from what the
# member picked, and read back for the feed card, the post page, the status
# image (ShareCard) and the link preview (PostOgCard).
#
# Nothing in it comes straight from the browser: the chapter and verse are
# re-parsed, the verse text is looked up, the burden is today's stored one,
# the notes are the member's own saved notes, and every string is clipped.
class ReadingShare
  NOTE_MAX = 1_000
  NOTES_MAX = 600
  BURDEN_MAX = 400
  VERSE_MAX = 600
  TAGLINE = "Read your Bible, pray every day"

  attr_reader :data

  # The hash to store on the post. chapter: a chapter Reference; verse_slug:
  # one verse of it (or blank); include_burden / include_notes: the member's ticks.
  def self.build(user:, chapter:, verse_slug: nil, include_burden: false, include_notes: false, has_note: false)
    chapter = chapter.chapter_reference
    verse = Scripture::Reference.from_slug(verse_slug.to_s) if verse_slug.present?
    verse = nil unless verse && !verse.chapter? && verse.chapter_reference == chapter
    verse_text = verse && verse_text_for(verse)
    verse = nil if verse_text.blank?

    prayer = include_burden ? ChapterPrayer.for(chapter) : nil
    notes = include_notes ? ChapterNote.for(user, chapter)&.body : nil
    streak = begin
      BibleHabit.for(user).streak
    rescue StandardError
      0
    end

    {
      "v" => 1,
      "chapter" => chapter.slug,
      "verse" => verse&.slug,
      "verse_text" => verse_text&.truncate(VERSE_MAX, separator: " "),
      "burden" => prayer&.burden.presence&.truncate(BURDEN_MAX, separator: " "),
      "notes" => notes.presence&.truncate(NOTES_MAX, separator: " "),
      "streak" => streak.to_i.clamp(0, 100_000),
      "has_note" => has_note ? true : false
    }.compact
  end

  # The KJV words of a verse (or short range), as the chapter page shows them.
  def self.verse_text_for(verse)
    Scripture::Passage.new(verse).primary.map(&:last).join(" ").squish.presence
  rescue StandardError
    nil
  end

  def self.from(post)
    data = post.reading_share
    return unless data.is_a?(Hash) && data["chapter"].present?

    share = new(data)
    share.chapter ? share : nil
  end

  def initialize(data)
    @data = data
  end

  def chapter
    @chapter ||= Scripture::Reference.from_slug(data["chapter"].to_s)&.chapter_reference
  end

  def verse
    return @verse if defined?(@verse)

    ref = Scripture::Reference.from_slug(data["verse"].to_s) if data["verse"].present?
    @verse = ref && ref.chapter_reference == chapter ? ref : nil
  end

  def verse_text = verse ? data["verse_text"].to_s.presence : nil
  def burden = data["burden"].to_s.presence
  def notes = data["notes"].to_s.presence
  def streak = data["streak"].to_i
  def note? = data["has_note"] == true

  # "🔥 12 days in the Word"
  def streak_label = streak > 1 ? "#{streak} days in the Word" : nil

  def title = "#{chapter}"
  def read_label = "Read #{chapter}"

  # The words a link preview, a search result or a status image leads with.
  def summary
    [ verse_text && "“#{verse_text}” (#{verse})", burden ].compact.join(" ").presence || "Read #{chapter} today."
  end
end
