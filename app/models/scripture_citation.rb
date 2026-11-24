# frozen_string_literal: true

# Which breaths quote which Bible references, so a scripture page can show
# "what people on Brethreign are saying" with one indexed query (and the
# sitemap can list every verse members talk about). Rebuilt whenever a
# breath is saved; `bin/rails scripture:citations` backfills.
class ScriptureCitation < ApplicationRecord
  belongs_to :post

  # Citations a scripture page should show: the same chapter for a chapter
  # page; for a verse page, citations whose verses overlap it.
  scope :matching, ->(reference) {
    rows = where(book: reference.book.position, chapter: reference.chapter)
    next rows if reference.chapter?

    rows.where(verse_start: ..reference.last_verse)
        .where("COALESCE(scripture_citations.verse_end, scripture_citations.verse_start) >= ?", reference.verse_start)
  }

  def self.sync(post)
    text = [ post.title, post.content&.to_plain_text ].compact.join("\n")
    refs = Scripture::Reference.find_all(text).first(20)
    transaction do
      where(post_id: post.id).delete_all
      now = Time.current
      rows = refs.map do |ref|
        { post_id: post.id, book: ref.book.position, chapter: ref.chapter,
          verse_start: ref.verse_start, verse_end: ref.verse_end, created_at: now }
      end
      insert_all(rows) if rows.any?
    end
  rescue StandardError => e
    Rails.logger.warn("[ScriptureCitation] post #{post.id}: #{e.class}: #{e.message}")
  end

  def reference
    Scripture::Reference.build(Scripture::Canon[book], chapter, verse_start, verse_end)
  end
end
