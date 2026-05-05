# frozen_string_literal: true

class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }

  scope :active, -> { where(archived_at: nil) }

  def unread?
    latest_message = conversation.messages.where.not(sender: user).order(created_at: :desc).first
    return false unless latest_message

    last_read_at.blank? || latest_message.created_at > last_read_at
  end

  def mark_read!
    update!(last_read_at: Time.current)
  end
end
