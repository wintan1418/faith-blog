# frozen_string_literal: true

class ResourceCategory < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Associations
  has_many :resources, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true

  # Scopes
  scope :ordered, -> { order(position: :asc) }
  scope :with_approved_resources, -> { joins(:resources).where(resources: { approved: true }).distinct }
end

