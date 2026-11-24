# frozen_string_literal: true

# One verse of a public-domain translation, loaded by `bin/rails scripture:import`
# from db/scripture/*.tsv.gz. Read-only after that.
class ScriptureVerse < ApplicationRecord
  # Public-domain translations we may show in full, in display order.
  TRANSLATIONS = {
    "kjv" => { name: "King James Version", short: "KJV" },
    "web" => { name: "World English Bible", short: "WEB" },
    "bsb" => { name: "Berean Standard Bible", short: "BSB" }
  }.freeze
  PRIMARY = "kjv"

  scope :at, ->(reference) {
    where(book: reference.book.position, chapter: reference.chapter, verse: reference.verses)
  }

  def self.imported?
    exists?(translation: PRIMARY)
  end
end
