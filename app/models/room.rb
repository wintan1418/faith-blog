# frozen_string_literal: true

class Room < ApplicationRecord
  extend FriendlyId
  include SearchIndexable
  friendly_id :name, use: :slugged

  # Enums
  enum :room_type, { general: 0, testimonies: 1, prayers: 2, struggles: 3, growth: 4, scripture: 5, questions: 6 }

  # Associations
  has_many :posts, dependent: :destroy
  has_many :room_memberships, dependent: :destroy
  has_many :members, through: :room_memberships, source: :user

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }
  validates :slug, presence: true, uniqueness: true

  # Scopes
  scope :public_rooms, -> { where(is_public: true) }
  scope :ordered, -> { order(position: :asc) }

  # Private rooms (is_public = false) are for their members and staff only.
  def accessible_by?(user)
    return true if is_public?
    return false unless user

    user.admin_or_moderator? || room_memberships.exists?(user: user)
  end

  # Counter cache updates
  def update_posts_count
    update_column(:posts_count, posts.published.count)
  end

  def update_members_count
    update_column(:members_count, room_memberships.count)
  end

  # Instance methods
  def moderators
    room_memberships.moderator.includes(:user).map(&:user)
  end

  def user_is_moderator?(user)
    return false unless user

    room_memberships.exists?(user: user, role: :moderator)
  end

  def search_indexable?
    is_public?
  end

  def search_index_urls
    [ search_url_helpers.room_url(self) ]
  end
end
