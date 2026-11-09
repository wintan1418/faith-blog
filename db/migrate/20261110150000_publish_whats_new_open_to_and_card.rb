# frozen_string_literal: true

# "What's new" for Open to, skill endorsements and the digital business card.
class PublishWhatsNewOpenToAndCard < ActiveRecord::Migration[8.1]
  TITLE = "New in Brethreign · Open to, endorsements and your card"
  BODY = <<~TEXT
    🟢 Say what you're open to — Hiring, new work, mentoring, freelance or volunteering. A coloured ring and badge show on your photo, for everyone or just your connections. [[open_to]]
    👍 Endorse a skill — Vouch for the people you're connected to with one tap on their skills. Your most-endorsed skills rise to the top.
    🪪 Your business card — A card with a QR code for church and work. Share it, send it on WhatsApp, or let someone save you to their contacts. [[card]]
  TEXT

  def up
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', #{connection.quote(TITLE)}, #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = #{connection.quote(TITLE)}")
  end
end
