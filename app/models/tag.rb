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
      find_or_create_by(name: name.strip.downcase)
    end
  end

  # Callbacks
  before_save :downcase_name

  private

  def downcase_name
    self.name = name.downcase
  end
end

