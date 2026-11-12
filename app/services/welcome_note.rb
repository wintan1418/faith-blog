# frozen_string_literal: true

# The founder's welcome to every member: an email, and a shorter note in their
# Brethreign inbox from the founder's own account so their first chat is with
# him and they can reply. Sent once per member (users.welcomed_at).
class WelcomeNote
  SIGN_OFF = [ "Yours faithfully,", "Oluwadare Juwon (Wintan)", "Chief Steward, Brethreign" ].freeze

  STEPS = [
    [ "Take your first breath.", "Share a thought, a verse, or simply what's on your heart today." ],
    [ "Ask for prayer, or pray for someone.", "Tap \"Praying\" on a request and the person will know they're not alone." ],
    [ "Find your room.", "Join rooms like Prayer Warriors, Bible Study, Young Adults or Brethren in Business." ],
    [ "Complete your Brethren Card,", "so the brethren you meet can truly know you." ],
    [ "Open the Bible and the games,", "for a reading plan, a quiz, or the verse of the day." ]
  ].freeze

  PSALM = [ "Behold, how good and how pleasant it is for brethren to dwell together in unity!", "Psalm 133:1" ].freeze
  HEBREWS = [ "And let us consider one another to provoke unto love and to good works.", "Hebrews 10:24" ].freeze

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

  def self.paragraphs
    [
      "Brethreign is a place for brothers and sisters in Christ to breathe together: to share what God is doing in us, " \
      "carry one another's burdens in prayer, open the Word side by side, and walk the road of faith in every part of life, " \
      "from our homes and churches to our work and dreams.",
      "We're still in our early and humble days, but we're full of faith for what God will grow here. And you're part of it."
    ]
  end

  def self.safety = "This is a safe place. We guard it carefully, so that every member can speak freely and be treated with love."
  def self.closing = "We're so glad you're here. Please pray for this family, and keep breathing."

  # The shorter inbox note from the founder.
  def self.inbox_text(user, existing:)
    <<~TEXT.strip
      Dear #{user.username},

      #{opening(existing: existing)} Brethreign is a home for brothers and sisters in Christ to breathe together: to share what God is doing, carry one another in prayer and open the Word side by side.

      "#{PSALM[0]}" (#{PSALM[1]})

      When you're ready, take your first breath, pray for someone, join a room and complete your Brethren Card. And if there's anything on your heart, reply here. I read every message.

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
