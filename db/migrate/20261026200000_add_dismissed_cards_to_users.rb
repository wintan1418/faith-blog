# frozen_string_literal: true

# Cards someone closed ("just joined us", release banner, welcome card) are
# remembered on their account, so they stay gone on every device.
class AddDismissedCardsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :dismissed_cards, :string, array: true, default: [], null: false
  end
end
