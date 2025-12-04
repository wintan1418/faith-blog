# frozen_string_literal: true

class RoomMembership < ApplicationRecord
  # Enums
  enum :role, { member: 0, moderator: 1 }

  # Associations
  belongs_to :user
  belongs_to :room, counter_cache: :members_count

  # Validations
  validates :user_id, uniqueness: { scope: :room_id, message: "is already a member of this room" }

  # Scopes
  scope :with_notifications, -> { where(notifications_enabled: true) }
end

