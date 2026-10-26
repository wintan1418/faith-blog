# frozen_string_literal: true

# Messages the AI moderator (or a moderator) removed. The text is kept for the
# review queue but never shown to the participants.
class AddModerationToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :removed_at, :datetime
    add_column :messages, :moderated_at, :datetime
  end
end
