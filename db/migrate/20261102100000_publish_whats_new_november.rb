# frozen_string_literal: true

# "What's new" for early November. Each body line is one slide; a trailing
# [[background_rain]] puts the on/off switch on that slide so people can try it.
class PublishWhatsNewNovember < ActiveRecord::Migration[8.1]
  TITLE = "New in Brethreign · November"
  BODY = <<~TEXT
    🌧 Background rain, your choice — Find the drifting scripture distracting? Switch it off here, or any time from your account menu. [[background_rain]]
    ↩️ Reply to a message — Tap a message and choose Reply to quote it. On a voice note, tap ⋯ beside it.
    📖 Copy & share scripture — Copy a verse or a whole passage from the Bible, or share it straight as a breath.
    🔔 Alerts that keep up — Opening an alert or tapping Mark all read updates at once, with no refresh.
    🗓 Schedule in your time — Scheduled breaths go live at the time you picked, wherever you are.
  TEXT

  def up
    execute "INSERT INTO announcements (kind, kicker, title, body, published_at, created_at, updated_at) " \
            "VALUES (0, 'What''s new', #{connection.quote(TITLE)}, #{connection.quote(BODY.strip)}, NOW(), NOW(), NOW())"
  end

  def down
    execute("DELETE FROM announcements WHERE kind = 0 AND title = #{connection.quote(TITLE)}")
  end
end
