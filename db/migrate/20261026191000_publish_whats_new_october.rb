# frozen_string_literal: true

# The first "What's new" pop-up: everything added in October. Each body line is one slide.
class PublishWhatsNewOctober < ActiveRecord::Migration[8.0]
  BODY = <<~TEXT
    💼 Professional profile — Share what you do, where you've served and what you studied. Settings → Professional.
    🎂 Birthdays — Add your birthday, and celebrate your brethren on their special day.
    🤝 Brethren you may know — Meet people from your assembly, your field and your city.
    🔖 Save breaths — Tap Save on any post and find it later in Bookmarks.
    💬 A new inbox — Cleaner chats, voice notes you can play back, and fewer repeat alerts.
    ⚡ Faster everywhere — Photos, the feed and messages load much quicker.
  TEXT

  def up
    # (No .squish here: it would flatten the line breaks that make the slides.)
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', 'New in Brethreign', #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = 'New in Brethreign'")
  end
end
