# frozen_string_literal: true

# The founder's welcome to every member: an email, and a shorter note in their
# Brethreign inbox from the founder's own account so their first chat is with
# him and they can reply. Sent once per member (users.welcomed_at).
class WelcomeNote
  SIGN_OFF = [ "Yours faithfully,", "Oluwadare Juwon (Wintan)", "Chief Steward, Brethreign" ].freeze

  # The three first steps in the welcome email: [key, title, line]. The
  # mailer links each key (profile settings, today's chapter, Rooms).
  STEPS = [
    [ :profile, "Complete your profile", "Add a photo and a few words, so the brethren you meet can truly know you." ],
    [ :bible, "Read today's chapter", "Open the Word alongside the family. A few quiet minutes is enough." ],
    [ :rooms, "Join a Room", "Prayer Warriors, Bible Study, Young Adults and more: find brethren who share your heart." ]
  ].freeze

  PSALM = [ "Behold, how good and how pleasant it is for brethren to dwell together in unity!", "Psalm 133:1" ].freeze

  def self.subject(user) = "Welcome home, #{user.username}"
  def self.preheader = "You're among family now. A note from the Brethreign family."

  # Members who joined before the note existed get the same note with an
  # opening that fits them.
  def self.opening(existing:)
    if existing
      "Whether you joined last week or many months ago, welcome home. You belong to a family."
    else
      "Welcome home. You've just joined a family."
    end
  end

  # One sentence for the welcome email (the inbox note says the same).
  def self.intro = "Brethreign is a home for brothers and sisters in Christ to breathe together: to share what God is doing, carry one another in prayer and open the Word side by side."

  def self.closing = "We're so glad you're here. Please pray for this family, and keep breathing."

  # The shorter inbox note from the founder.
  def self.inbox_text(user, existing:)
    <<~TEXT.strip
      Dear #{user.username},

      #{opening(existing: existing)} #{intro}

      "#{PSALM[0]}" (#{PSALM[1]})

      When you're ready, complete your profile, read today's chapter and join a Room. And if there's anything on your heart, reply here. I read every message.

      Please pray for this family, and keep breathing.

      Wintan
      Chief Steward, Brethreign
    TEXT
  end

  # The founder's account: WELCOME_FROM (a username), else the first super admin, else the first admin.
  def self.sender
    name = ENV["WELCOME_FROM"].to_s.strip.delete_prefix("@")
    (name.present? && User.find_by(username: name)) ||
      User.where(role: :super_admin).order(:id).first ||
      User.where(role: :admin).order(:id).first
  end

  def self.deliver(user, existing: false)
    return if user.welcomed_at.present? || !user.active?

    WelcomeMailer.with(user: user, existing: existing).welcome.deliver_later if user.email.present? && user.email_notifications_enabled
    send_inbox_note(user, existing: existing)
    user.update_column(:welcomed_at, Time.current)
  end

  def self.send_inbox_note(user, existing:)
    from = sender
    return if from.nil? || from == user

    conversation = Conversation.find_or_create_between!(from, user)
    conversation.messages.create!(sender: from, body: inbox_text(user, existing: existing), quiet: true)
  rescue StandardError => e
    Rails.logger.warn("[WelcomeNote] inbox note to user #{user.id} failed: #{e.class}: #{e.message}")
  end
end
