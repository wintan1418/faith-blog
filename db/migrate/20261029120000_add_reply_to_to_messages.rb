# frozen_string_literal: true

class AddReplyToToMessages < ActiveRecord::Migration[8.0]
  def change
    # Reply to one message in a chat (WhatsApp-style quote). Nullified if the
    # original is ever hard-deleted.
    add_reference :messages, :reply_to, foreign_key: { to_table: :messages, on_delete: :nullify }, index: true
  end
end
