# frozen_string_literal: true

class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy

  scope :recent, -> { order(Arel.sql("COALESCE(last_message_at, conversations.created_at) DESC")) }

  def self.between(user, other_user)
    joins(:conversation_participants)
      .where(conversation_participants: { user_id: [ user.id, other_user.id ] })
      .group("conversations.id")
      .having("COUNT(DISTINCT conversation_participants.user_id) = 2")
      .first
  end

  def self.find_or_create_between!(user, other_user)
    existing = between(user, other_user)
    return existing if existing

    transaction do
      conversation = create!
      conversation.conversation_participants.create!(user: user)
      conversation.conversation_participants.create!(user: other_user)
      conversation
    end
  end

  def other_participant_for(user)
    participants.detect { |participant| participant.id != user.id }
  end

  def participant_for(user)
    conversation_participants.find_by(user: user)
  end

  def mark_read_for!(user)
    participant_for(user)&.mark_read!
  end

  def unread_for?(user)
    participant_for(user)&.unread? || false
  end
end
