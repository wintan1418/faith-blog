# frozen_string_literal: true

# A member's own notes on one Bible chapter ("My notes" on the chapter page).
# Private: shown only to the writer, and put on a shared reading card only
# when they tick "Include my notes" (Post.build_reading_share).
class ChapterNote < ApplicationRecord
  MAX = 4_000

  belongs_to :user

  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :body, presence: true, length: { maximum: MAX }

  def self.for(user, chapter)
    return unless user && chapter

    find_by(user: user, slug: chapter.chapter_reference.slug)
  end

  # Saves (or, when the words are blank, deletes) this member's notes on a chapter.
  def self.write!(user, chapter, body)
    note = find_or_initialize_by(user: user, slug: chapter.chapter_reference.slug)
    text = body.to_s.gsub(/\r\n?/, "\n").strip.first(MAX)
    if text.blank?
      note.destroy! if note.persisted?
      return nil
    end
    note.update!(body: text)
    note
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
