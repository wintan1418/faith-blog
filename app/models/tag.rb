# frozen_string_literal: true

class Tag < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Associations
  has_many :post_tags, dependent: :destroy
  has_many :posts, through: :post_tags

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 50 }
  validates :slug, presence: true, uniqueness: true

  # Scopes
  scope :popular, -> { order(usage_count: :desc) }
  scope :trending, -> { where("updated_at > ?", 7.days.ago).order(usage_count: :desc) }

  # Class methods
  def self.find_or_create_by_names(names)
    names.map do |name|
      normalized = name.strip.downcase
      begin
        find_or_create_by(name: normalized)
      rescue ActiveRecord::RecordNotUnique
        # Lost a race against a concurrent create for the same tag — the unique
        # index on `name` did its job; just fetch the row the winner inserted.
        find_by(name: normalized) || raise
      end
    end
  end

  # Callbacks
  before_save :downcase_name

  private

  def downcase_name
    self.name = name.downcase
  end
end
