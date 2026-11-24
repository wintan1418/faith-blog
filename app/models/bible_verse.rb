# frozen_string_literal: true

class BibleVerse < ApplicationRecord
  include SearchIndexable

  validates :text, presence: true, length: { minimum: 4, maximum: 800 }
  validates :reference, length: { maximum: 120 }, allow_blank: true

  scope :active,  -> { where(active: true) }

  # Admins often paste verses as “text” — Book 1:2; keep just the words and
  # the plain reference so the feed can show them and open the chapter.
  before_validation do
    self.text = self.class.clean_text(text) if text
    self.reference = self.class.clean_reference(reference) if reference
  end

  def self.clean_reference(value)
    value.to_s.strip.sub(/\A[\p{Pd}~\s]+/, "").strip
  end

  def self.clean_text(value)
    value.to_s.strip.sub(/\A["“”‘’']+/, "").sub(/["“”‘’']+\z/, "").strip
  end

  # "Mark 9:23" → "Mark 9" (the chapter to open).
  def self.chapter_of(reference)
    clean_reference(reference).sub(/:[\d\-–, ]+\z/, "").strip
  end
  scope :ordered, -> { order(position: :asc, created_at: :desc) }

  # Stable "verse of the day" — same verse for everyone on a given day,
  # rotates by day-of-year, pulls only from active rows.
  def self.of_the_day
    pool = active.ordered.to_a
    return nil if pool.empty?

    pool[Date.current.yday % pool.size]
  end

  # An active verse has a scripture page (/scripture/<slug>) in the sitemap.
  def search_indexable?
    active? && reference.present?
  end

  def search_index_urls
    [ search_url_helpers.scripture_page_url(slug: SitemapsController.scripture_slug(reference)) ]
  end
end
