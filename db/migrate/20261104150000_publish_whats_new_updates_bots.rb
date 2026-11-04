# frozen_string_literal: true

# "What's new" for the Updates bots and the new chat features. Each body line
# is one slide; [[updates]] puts an "Open Updates" button on that slide.
class PublishWhatsNewUpdatesBots < ActiveRecord::Migration[8.1]
  TITLE = "New in Brethreign · Updates"
  BODY = <<~TEXT
    📰 The world, in your Updates tab — Brethreign's bots bring news from around the world every few hours: world, politics, tech & AI, science, health, food and faith. [[updates]]
    🏆 Sport, jobs and free courses — Results and big moments in sport, remote jobs open to anyone, and free courses and scholarships. Never pay to apply for anything.
    🎛 Make it yours — Filter by bot or topic, and switch off any bot you don't want under "Choose which bots you see".
    📎 Send documents in chats — Attach PDFs, Word, Excel and more with the paperclip.
    ↪️ Forward and share messages — Tap a message to forward it to other chats, or share it to WhatsApp and more.
  TEXT

  def up
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', #{connection.quote(TITLE)}, #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = #{connection.quote(TITLE)}")
  end
end
