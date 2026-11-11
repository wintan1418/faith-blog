# frozen_string_literal: true

# One entry in an Office thread.
#   user      - what the founder typed (or imported notes: payload["imported"])
#   assistant - the model's reply; payload["tool_calls"] lists the tools it asked for and
#               payload["raw"] keeps the provider's own content so tool turns replay exactly
#   tool      - a tool's result; payload["card"] is what the founder sees and acts on
#   card      - a card made from the UI (e.g. "Use in a breath"), not from a tool call
class OfficeMessage < ApplicationRecord
  enum :role, { user: 0, assistant: 1, tool: 2, card: 3 }

  belongs_to :conversation, class_name: "OfficeConversation", foreign_key: :office_conversation_id,
                            inverse_of: :messages
  has_one_attached :image

  validates :content, length: { maximum: 200_000 }

  after_create_commit :append_to_thread

  def tool_name = payload["name"]
  def tool_calls = Array(payload["tool_calls"])
  def card_data = payload["card"] || {}
  def card_kind = card_data["kind"]
  def imported? = payload["imported"] == true
  def failed? = payload["error"] == true

  # Merges attrs into the card and re-renders it for everyone watching.
  def update_card!(attrs)
    update!(payload: payload.merge("card" => card_data.merge(attrs.deep_stringify_keys)))
    broadcast_replace_to conversation.stream, target: ActionView::RecordIdentifier.dom_id(self),
                                              partial: "admin/office/messages/message", locals: { message: self }
  end

  private

  def append_to_thread
    broadcast_append_to conversation.stream, target: "office_messages",
                                             partial: "admin/office/messages/message", locals: { message: self }
  end
end
