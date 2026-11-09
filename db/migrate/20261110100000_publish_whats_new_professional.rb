# frozen_string_literal: true

# "What's new" for professional profiles, the LinkedIn import, the chess
# ladder and the chat fixes. Each body line is one slide; [[professional]],
# [[linkedin]] and [[chess]] put a button on that slide.
class PublishWhatsNewProfessional < ActiveRecord::Migration[8.1]
  TITLE = "New in Brethreign · Professional profiles"
  BODY = <<~TEXT
    💼 Your professional profile — Every profile now has Breaths, Professional and About tabs. A strength meter shows what to add next. [[professional]]
    🔗 Import from LinkedIn — Upload your LinkedIn PDF or data export, tick what to bring across, and your profile is filled in a minute. [[linkedin]]
    🎓 Certifications, languages and more — Add licenses and certificates, the languages you speak and your industry. Volunteer and church roles get their own section.
    🤝 Brethren you may know — Fresh cards that show the friends you share. "See all" now opens every suggestion, ready to connect.
    ♞ The chess ladder — Ten puzzles that get harder as you climb, at Easy, Medium or Hard. Three tries each. How high can you go? [[chess]]
    📄 Files and photos in chats — PDFs open and share properly, any photo can be saved, images paste straight in, and on a computer Enter sends.
    ⏱️ Schedule a draft — Pick a time in the draft editor and your breath goes out on its own.
  TEXT

  def up
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', #{connection.quote(TITLE)}, #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = #{connection.quote(TITLE)}")
  end
end
