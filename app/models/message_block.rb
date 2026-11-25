# frozen_string_literal: true

# A block between two members (named from when it only stopped messages).
# It stops messages and hides each other's breaths, reposts and comments
# (User#blocked_user_ids).
class MessageBlock < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: { scope: :blocker_id }
  validate :cannot_block_self

  after_create_commit :sever_ties

  # Takes users or ids.
  def self.between?(user, other_user)
    a = user.is_a?(User) ? user.id : user
    b = other_user.is_a?(User) ? other_user.id : other_user
    return false if a.blank? || b.blank?

    where(blocker_id: a, blocked_id: b).or(where(blocker_id: b, blocked_id: a)).exists?
  end

  private

  # A block ends the relationship: no connection (so no Brethren Card access),
  # no shared contact details and no follow either way. Unblocking doesn't bring them back.
  def sever_ties
    ConnectionRequest.where(sender_id: blocker_id, receiver_id: blocked_id)
                     .or(ConnectionRequest.where(sender_id: blocked_id, receiver_id: blocker_id)).destroy_all
    Follow.where(follower_id: blocker_id, following_id: blocked_id)
          .or(Follow.where(follower_id: blocked_id, following_id: blocker_id)).destroy_all
    ContactShare.where(owner_id: blocker_id, viewer_id: blocked_id)
                .or(ContactShare.where(owner_id: blocked_id, viewer_id: blocker_id)).destroy_all
  end

  def cannot_block_self
    errors.add(:blocked_id, "cannot be yourself") if blocker_id == blocked_id
  end
end
