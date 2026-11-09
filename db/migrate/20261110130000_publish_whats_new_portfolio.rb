# frozen_string_literal: true

# "What's new" for the Portfolio tab. [[portfolio]] puts an "Add your work"
# button on the first slide.
class PublishWhatsNewPortfolio < ActiveRecord::Migration[8.1]
  TITLE = "New in Brethreign · Portfolio"
  BODY = <<~TEXT
    🗂️ Your portfolio — A new Portfolio tab on your profile for the work you're proud of: designs, apps, writing, photos, buildings, events, projects you led. [[portfolio]]
    🖼️ Photos, a link and a PDF — Each piece gets up to 8 photos, the story behind it, your part, the skills you used, a link and a case-study PDF.
    🔗 Easy to share — Every piece has its own page with a link that previews nicely on WhatsApp. Put your best work first with the arrows.
  TEXT

  def up
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', #{connection.quote(TITLE)}, #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = #{connection.quote(TITLE)}")
  end
end
