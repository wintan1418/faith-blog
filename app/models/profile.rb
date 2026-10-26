# frozen_string_literal: true

class Profile < ApplicationRecord
  include AttachmentValidatable

  AVATAR_MAX_BYTES = 10.megabytes

  # Associations
  belongs_to :user
  has_one_attached :avatar

  # Validations
  validates :bio, length: { maximum: 500 }
  validates :location, length: { maximum: 100 }
  validates :faith_background, length: { maximum: 200 }
  validates :website, length: { maximum: 255 }
  validate  :avatar_content_type_and_size

  def avatar_content_type_and_size
    validate_image_attachment(:avatar, max_bytes: AVATAR_MAX_BYTES)
  end

  # Professional headline and skills (LinkedIn-style). Skills come in as a comma list.
  MAX_SKILLS = 30
  validates :headline, length: { maximum: 120 }
  validate :skills_are_short

  def skills_list=(value)
    self.skills = value.to_s.split(",").map { |s| s.squish.first(40) }.compact_blank.uniq { |s| s.downcase }.first(MAX_SKILLS)
  end

  def skills_list = skills.join(", ")

  def skills_are_short
    errors.add(:skills, "can have at most #{MAX_SKILLS}") if skills.size > MAX_SKILLS
  end

  # Avatar variant helpers
  def avatar_thumbnail
    avatar.variant(resize_to_fill: [ 100, 100 ])
  end

  def avatar_medium
    avatar.variant(resize_to_fill: [ 200, 200 ])
  end

  def avatar_large
    avatar.variant(resize_to_fill: [ 400, 400 ])
  end
end
