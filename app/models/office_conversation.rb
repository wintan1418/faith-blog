# frozen_string_literal: true

# A thread in Admin → Office: the founder talking with the assistant.
class OfficeConversation < ApplicationRecord
  DEFAULT_TITLE = "New conversation"

  belongs_to :user
  has_many :messages, -> { order(:id) }, class_name: "OfficeMessage", inverse_of: :conversation, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }

  scope :recent, -> { order(Arel.sql("COALESCE(office_conversations.last_message_at, office_conversations.created_at) DESC")) }

  # Turbo stream every page showing this thread listens to.
  def stream = [ self, :office ]

  def untitled? = title.blank? || title == DEFAULT_TITLE

  # Name a fresh thread after the first thing the founder said in it.
  def title_from!(text)
    return unless untitled?

    line = text.to_s.lines.map(&:strip).find(&:present?).to_s.gsub(/[#*_`>]/, "").squish
    update!(title: line.truncate(60, separator: " ", omission: "…").presence || DEFAULT_TITLE)
  end

  def touch_last_message!
    update_columns(last_message_at: Time.current, updated_at: Time.current)
  end

  # A reply is being written. A reply that never finished (a worker died)
  # stops counting after STALE_AFTER so the thread can't get stuck.
  STALE_AFTER = 10.minutes
  def busy? = thinking? && updated_at > STALE_AFTER.ago

  # Shows or hides the "thinking" row for everyone watching the thread.
  def thinking!(value)
    update_columns(thinking: value, updated_at: Time.current)
    broadcast_replace_to stream, target: "office_status", partial: "admin/office/conversations/status",
                                 locals: { conversation: self }
  end
end
