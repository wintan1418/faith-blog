# frozen_string_literal: true

class Profile < ApplicationRecord
  # Associations
  belongs_to :user
  has_one_attached :avatar

  # Validations
  validates :bio, length: { maximum: 500 }
  validates :location, length: { maximum: 100 }
  validates :faith_background, length: { maximum: 200 }
  validates :website, length: { maximum: 255 }

  # Avatar variant helpers
  def avatar_thumbnail
    avatar.variant(resize_to_fill: [100, 100])
  end

  def avatar_medium
    avatar.variant(resize_to_fill: [200, 200])
  end

  def avatar_large
    avatar.variant(resize_to_fill: [400, 400])
  end
end

