# frozen_string_literal: true

# A "see also" link between verses (OpenBible.info, CC BY, after the Treasury
# of Scripture Knowledge). `votes` is how many readers found the link helpful.
class ScriptureCrossReference < ApplicationRecord
  ATTRIBUTION = "Cross-references: OpenBible.info (CC BY)"

  scope :from_reference, ->(reference) {
    where(book: reference.book.position, chapter: reference.chapter, verse: reference.verses)
  }

  # The most-voted links out of a verse or range, as References, best first.
  def self.top_for(reference, limit: 6)
    return [] if reference.chapter?

    from_reference(reference).order(votes: :desc, id: :asc).limit(limit * 3).filter_map do |row|
      ref = row.target
      ref unless ref.nil? || ref.slug == reference.slug
    end.uniq(&:slug).first(limit)
  end

  def target
    book = Scripture::Canon[to_book]
    end_verse = to_verse_end if to_chapter_end.nil? || to_chapter_end == to_chapter
    Scripture::Reference.build(book, to_chapter, to_verse, end_verse) if book
  end
end
