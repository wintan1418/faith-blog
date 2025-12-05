class ConnectionRequest < ApplicationRecord
  belongs_to :sender, class_name: 'User'
  belongs_to :receiver, class_name: 'User'

  enum :status, { pending: 0, accepted: 1, declined: 2 }

  validates :sender_id, uniqueness: { scope: :receiver_id, message: "has already sent a request to this user" }
  validate :cannot_request_self
  validate :sender_has_complete_card

  scope :incoming, ->(user) { where(receiver: user) }
  scope :outgoing, ->(user) { where(sender: user) }
  scope :pending_for, ->(user) { incoming(user).pending }

  after_create :create_notification
  after_update :notify_on_acceptance

  def self.between(user1, user2)
    where(sender: user1, receiver: user2)
      .or(where(sender: user2, receiver: user1))
      .first
  end

  def self.connected?(user1, user2)
    between(user1, user2)&.accepted?
  end

  private

  def cannot_request_self
    if sender_id == receiver_id
      errors.add(:receiver_id, "cannot be yourself")
    end
  end

  def sender_has_complete_card
    if sender&.brethren_card.blank? || !sender.brethren_card.complete?
      errors.add(:base, "You must complete your Brethren Card before sending connection requests")
    end
  end

  def create_notification
    Notification.create!(
      user: receiver,
      actor: sender,
      notification_type: :connection_request,
      notifiable: self
    )
  end

  def notify_on_acceptance
    return unless saved_change_to_status? && accepted?
    
    Notification.create!(
      user: sender,
      actor: receiver,
      notification_type: :connection_accepted,
      notifiable: self
    )
  end
end

