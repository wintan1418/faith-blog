# frozen_string_literal: true

# A Prayer Circle: a small private group — cell group, family, close
# brethren — with its own quiet stream (CircleBreath) and a shared prayer
# list (CirclePrayer). Everything inside is members-only; joining happens
# by invite link only.
class Circle < ApplicationRecord
  belongs_to :owner, class_name: "User"

  has_many :circle_memberships, dependent: :destroy
  has_many :members, through: :circle_memberships, source: :user
  has_many :breaths, class_name: "CircleBreath", dependent: :destroy
  has_many :prayers, class_name: "CirclePrayer", dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :description, length: { maximum: 500 }, allow_blank: true

  before_validation :ensure_slug, :ensure_invite_code, on: :create

  def to_param = slug

  def member?(user)
    return false unless user

    circle_memberships.exists?(user_id: user.id)
  end

  def owned_by?(user)
    user.present? && owner_id == user.id
  end

  # Fresh code kills old invite links — for when one leaks beyond the circle.
  def rotate_invite_code!
    update!(invite_code: self.class.generate_invite_code)
  end

  def self.generate_invite_code
    SecureRandom.base58(12)
  end

  private

  def ensure_slug
    return if slug.present?

    base = name.to_s.parameterize.presence || "circle"
    self.slug = "#{base}-#{SecureRandom.hex(3)}"
  end

  def ensure_invite_code
    self.invite_code ||= self.class.generate_invite_code
  end
end
