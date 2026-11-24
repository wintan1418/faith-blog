# frozen_string_literal: true

# Small named values for search indexing (for now the generated IndexNow key).
class SeoSetting < ApplicationRecord
  validates :key, presence: true

  def self.[](key)
    find_by(key: key)&.value
  end

  # Returns the stored value, creating it from the block the first time.
  # Two processes racing here both end up with the same (first) value.
  def self.fetch(key)
    self[key] || create!(key: key, value: yield).value
  rescue ActiveRecord::RecordNotUnique
    self[key]
  end
end
