# frozen_string_literal: true

# Who may see a member's Brethren Card email and WhatsApp number. Each field
# has its own setting: 0 only me (the default), 1 people I choose, 2 all my
# connections, 3 everyone. Privacy first: every existing card starts at
# "only me", whatever it showed before, and members who had filled either in
# get a one-time notice asking them to choose.
class AddContactPrivacyToBrethrenCards < ActiveRecord::Migration[8.1]
  def up
    add_column :brethren_cards, :email_visibility, :integer, default: 0, null: false
    add_column :brethren_cards, :whatsapp_visibility, :integer, default: 0, null: false
    add_column :users, :contact_privacy_notice_pending, :boolean, default: false, null: false

    execute <<~SQL.squish
      UPDATE users SET contact_privacy_notice_pending = TRUE
      WHERE id IN (
        SELECT user_id FROM brethren_cards
        WHERE COALESCE(TRIM(email), '') <> '' OR COALESCE(TRIM(whatsapp_number), '') <> ''
      )
    SQL
  end

  def down
    remove_column :users, :contact_privacy_notice_pending
    remove_column :brethren_cards, :whatsapp_visibility
    remove_column :brethren_cards, :email_visibility
  end
end
