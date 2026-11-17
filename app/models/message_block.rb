# frozen_string_literal: true

# A block between two members (named from when it only stopped messages).
# It stops messages and hides each other's breaths, reposts and comments
# (User#blocked_user_ids).
class MessageBlock < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: { scope: :blocker_id }
  validate :cannot_block_self

  def self.between?(user, other_user)
    where(blocker: user, blocked: other_user).or(where(blocker: other_user, blocked: user)).exists?
  end

  private

  def cannot_block_self
    errors.add(:blocked_id, "cannot be yourself") if blocker_id == blocked_id
  end
end
