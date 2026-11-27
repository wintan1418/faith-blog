# frozen_string_literal: true

class Notification < ApplicationRecord
  # Enums
  enum :notification_type, {
    new_comment: 0,
    comment_reply: 1,
    new_follower: 2,
    post_featured: 3,
    new_post_in_room: 4,
    resource_approved: 5,
    resource_rejected: 6,
    mentioned: 7,
    post_liked: 8,
    comment_liked: 9,
    connection_request: 10,
    connection_accepted: 11,
    post_reshared: 12,
    direct_message: 13,
    breath_from_followee: 14,
    everyone_mention:     15,
    prayer_joined:        16,
    prayer_answered:      17,
    post_blocked:         18,
    post_held_for_review: 19,
    post_moderation_approved: 20,
    thread_new_voice:     21,
    badge_earned:         22,
    circle_breath:          23,
    circle_prayer:          24,
    circle_prayer_answered: 25,
    birthday:               26,
    content_removed:        27,
    skill_endorsed:         28,
    app_update:             29,
    rank_up:                30,
    series_new_part:        31,
    bible_reminder:         32,
    page_invite:            33,
    page_new_follower:      34,
    page_verified:          35,
    page_mentioned:         36,
    feedback_request:       37,
    contact_shared:         38
  }

  # Associations
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  # Validations
  validates :notification_type, presence: true
  validate :not_between_blocked_members, on: :create

  # Alerts one member causes another (likes, comments, mentions, follows,
  # requests…). None of these are created between people where either has
  # blocked the other. Moderation and system alerts aren't affected.
  SOCIAL_TYPES = %w[
    new_comment comment_reply new_follower mentioned post_liked comment_liked connection_request
    connection_accepted post_reshared direct_message breath_from_followee everyone_mention prayer_joined
    prayer_answered thread_new_voice circle_breath circle_prayer circle_prayer_answered birthday skill_endorsed
    series_new_part page_invite page_mentioned contact_shared
  ].freeze

  before_create :conceal_anonymous_author

  after_create_commit :deliver_email_notification
  after_create_commit :deliver_push_notification
  after_create_commit -> { user&.broadcast_unread_counts }

  # Scopes
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  # Everything except chat messages. Messages live in the Inbox (with its own badge),
  # like LinkedIn, so they don't bury comments, reactions and follows in Alerts.
  scope :activity, -> { where.not(notification_type: :direct_message) }

  # Instance methods
  def mark_as_read!
    update(read_at: Time.current) unless read?
  end

  def read?
    read_at.present?
  end

  def unread?
    !read?
  end

  # The icon that marks each type on the web (the push and email text keep
  # their emoji; the site shows a real icon instead).
  WEB_ICONS = {
    new_comment: "comment", comment_reply: "reply", new_follower: "userplus",
    post_featured: "star", new_post_in_room: "users", resource_approved: "library",
    resource_rejected: "library", mentioned: "megaphone", post_liked: "heart",
    comment_liked: "heart", connection_request: "handshake", connection_accepted: "handshake",
    post_reshared: "repost", direct_message: "mail", breath_from_followee: "leaf",
    everyone_mention: "megaphone", prayer_joined: "pray", prayer_answered: "answered",
    post_blocked: "shield", post_held_for_review: "shield", post_moderation_approved: "checkcircle",
    thread_new_voice: "comment", badge_earned: "trophy", circle_breath: "users",
    circle_prayer: "pray", circle_prayer_answered: "answered", birthday: "cake",
    content_removed: "shield", skill_endorsed: "thumbsup", app_update: "smartphone",
    rank_up: "sprout", series_new_part: "library", bible_reminder: "bookopen",
    page_invite: "building", page_new_follower: "userplus", page_verified: "badgecheck", page_mentioned: "megaphone",
    feedback_request: "chat", contact_shared: "mail"
  }.freeze

  def web_icon
    WEB_ICONS[notification_type.to_sym] || "bell"
  end

  # Push and email text (keeps its emoji).
  def message = message_text(emoji: true)

  # The same words for the site, where the row's icon does the emoji's job.
  def web_message = message_text(emoji: false)

  def message_text(emoji:)
    e = ->(mark) { emoji ? mark : "" }
    case notification_type.to_sym
    when :new_comment
      "#{actor&.display_name || 'Someone'} commented on your post"
    when :comment_reply
      "#{actor&.display_name || 'Someone'} replied to your comment"
    when :new_follower
      "#{actor&.display_name || 'Someone'} started following you"
    when :post_featured
      "Your post has been featured!"
    when :new_post_in_room
      "New post in a room you follow"
    when :resource_approved
      "Your resource has been approved"
    when :resource_rejected
      "Your resource was not approved"
    when :mentioned
      "#{voice_name} mentioned you"
    when :post_liked
      "#{actor&.display_name || 'Someone'} reacted to your post"
    when :comment_liked
      "#{actor&.display_name || 'Someone'} reacted to your comment"
    when :connection_request
      "#{actor&.display_name || 'Someone'} wants to know you more"
    when :connection_accepted
      "#{actor&.display_name || 'Someone'} accepted your connection request"
    when :post_reshared
      "#{voice_name} reshared your post"
    when :direct_message
      direct_message_text
    when :breath_from_followee
      "#{actor&.display_name || 'Someone'} breathed"
    when :everyone_mention
      "#{actor&.display_name || 'Someone'} mentioned everyone"
    when :thread_new_voice
      "#{actor&.display_name || 'Someone'} added their breath to a thread you're in#{e.(" 🧵")}"
    when :badge_earned
      badge = notifiable.respond_to?(:info) ? notifiable.info : nil
      badge ? "You earned the #{badge[:name]} badge#{e.(" #{badge[:emoji]}")}" : "You earned a new badge#{e.(" ✦")}"
    when :rank_up
      rank = notifiable.respond_to?(:rank) ? notifiable.rank : nil
      rank ? "You're now #{rank.a_name}#{e.(" #{rank.emoji}")}. Keep encouraging the brethren." : "You reached a new rank#{e.(" 🌱")}"
    when :prayer_joined
      "#{actor&.display_name || 'Someone'} joined your prayer chain"
    when :prayer_answered
      "A prayer you joined was just marked answered#{e.(" 🌟")}"
    when :post_blocked
      "Your post couldn't be published — it appears to violate our community guidelines."
    when :post_held_for_review
      "Your post is held for moderator review — we'll get back to you shortly."
    when :post_moderation_approved
      "Good news — your post passed moderation review and is now live."
    when :circle_breath
      "#{actor&.display_name || 'Someone'} breathed in your circle #{circle_name_suffix}"
    when :circle_prayer
      "#{actor&.display_name || 'Someone'} added a prayer to #{circle_name_suffix('your circle')}#{e.(" 🙏")}"
    when :circle_prayer_answered
      "A prayer in #{circle_name_suffix('your circle')} was marked answered#{e.(" 🌟")}"
    when :content_removed
      if notifiable.is_a?(Page)
        "#{e.("🛡 ")}A picture on your page “#{notifiable.name}” was removed because it breaks our community guidelines. Please choose another."
      elsif notifiable.is_a?(PortfolioItem)
        "#{e.("🛡 ")}“#{notifiable.title.to_s.truncate(40)}” was hidden from your portfolio because it breaks our community guidelines. Edit it or remove it."
      else
        "#{e.("🛡 ")}Your profile photo was removed because it breaks our community guidelines. Please choose another."
      end
    when :skill_endorsed
      "#{actor&.display_name || 'Someone'} endorsed you for #{notifiable.try(:skill) || 'a skill'}#{e.(" 👍")}"
    when :app_update
      "#{e.("📲 ")}Brethreign #{notifiable.try(:latest_version)} is out. Update the app to get the newest features and fixes."
    when :series_new_part
      series = notifiable.try(:series)
      part = notifiable.try(:series_position)
      "#{actor&.display_name || 'Someone'} added #{part ? "Part #{part}" : 'a new part'} to “#{series&.title || 'a series you follow'}”#{e.(" 📖")}"
    when :bible_reminder
      reading = notifiable.try(:portion)&.label
      "Have you read your Bible today?#{" Today: #{reading}." if reading}#{e.(" 📖")}"
    when :page_invite
      "#{actor&.display_name || 'Someone'} invited you to help run #{page_name_for_alert} as #{notifiable.try(:role_label)&.downcase&.then { |r| r == 'admin' ? 'an admin' : "an #{r}" } || 'a member of its team'}"
    when :page_new_follower
      followers_alert_text
    when :page_verified
      "#{page_name_for_alert} is now verified#{e.(" ✓")}"
    when :page_mentioned
      "#{notifiable.try(:author_name) || 'Someone'} mentioned your page"
    when :feedback_request
      "#{e.("💬 ")}We'd love your feedback — #{notifiable.try(:duration_label) || '30 seconds'}#{": #{notifiable.title}" if notifiable.respond_to?(:title)}"
    when :contact_shared
      "#{actor&.display_name || 'Someone'} shared their contact details with you"
    when :birthday
      "#{e.("🎂 ")}It's #{actor&.display_name || 'a brother or sister'}'s birthday today. Wish them well!"
    else
      "You have a new notification"
    end
  end

  def target_path
    case notification_type.to_sym
    when :new_comment, :comment_reply
      Rails.application.routes.url_helpers.post_path(notifiable.post)
    when :new_follower
      # The follower may have deleted their account since (actor is then nil).
      if actor
        Rails.application.routes.url_helpers.user_path(actor.username)
      else
        Rails.application.routes.url_helpers.notifications_path
      end
    when :badge_earned, :rank_up
      Rails.application.routes.url_helpers.user_path(user.username)
    when :post_featured, :post_liked, :post_reshared, :mentioned, :breath_from_followee, :series_new_part, :everyone_mention, :prayer_joined, :prayer_answered, :post_blocked, :post_held_for_review, :post_moderation_approved, :comment_liked, :thread_new_voice
      post = underlying_post
      if post
        Rails.application.routes.url_helpers.post_path(post)
      else
        Rails.application.routes.url_helpers.notifications_path
      end
    when :new_post_in_room
      room = notifiable.respond_to?(:room) ? notifiable.room : notifiable
      Rails.application.routes.url_helpers.room_path(room)
    when :resource_approved, :resource_rejected
      Rails.application.routes.url_helpers.resources_item_path(notifiable)
    when :connection_request, :connection_accepted
      Rails.application.routes.url_helpers.my_connections_path
    when :direct_message
      Rails.application.routes.url_helpers.conversation_path(notifiable.conversation)
    when :circle_breath, :circle_prayer, :circle_prayer_answered
      Rails.application.routes.url_helpers.circle_path(notifiable.circle)
    when :birthday
      Rails.application.routes.url_helpers.user_path(actor.username)
    when :contact_shared
      Rails.application.routes.url_helpers.brethren_card_path(actor.username)
    when :skill_endorsed
      Rails.application.routes.url_helpers.user_path(user.username, tab: "professional")
    when :bible_reminder
      chapter = notifiable.try(:portion)&.first
      routes = Rails.application.routes.url_helpers
      chapter ? routes.scripture_page_path(chapter.slug) : routes.feed_path
    when :page_invite
      Rails.application.routes.url_helpers.org_page_path(notifiable.page) # the invite banner is there
    when :page_new_follower, :page_verified
      Rails.application.routes.url_helpers.org_page_path(notifiable)
    when :page_mentioned
      post = underlying_post
      post ? Rails.application.routes.url_helpers.post_path(post) : Rails.application.routes.url_helpers.notifications_path
    when :feedback_request
      Rails.application.routes.url_helpers.feedback_survey_path(notifiable)
    when :app_update
      Rails.application.routes.url_helpers.app_update_store_path # straight on to the Play Store
    when :content_removed
      if notifiable.is_a?(Page)
        Rails.application.routes.url_helpers.manage_org_page_path(notifiable)
      elsif notifiable.is_a?(PortfolioItem)
        Rails.application.routes.url_helpers.edit_settings_portfolio_item_path(notifiable)
      else
        Rails.application.routes.url_helpers.edit_settings_profile_path
      end
    else
      Rails.application.routes.url_helpers.notifications_path
    end
  rescue StandardError
    Rails.application.routes.url_helpers.notifications_path
  end

  # The Post this notification is "about", whatever record was stored as the
  # notifiable (Post, Comment, Like, Reshare…). Reaction notifications store
  # the Like, which has no #post — passing it straight to post_path built
  # /posts/<like-id>, a link to a breath that doesn't exist (or, on an id
  # collision, to somebody else's breath entirely).
  def underlying_post
    n = notifiable
    return n if n.is_a?(Post)
    return n.post if n.respond_to?(:post) && n.post.is_a?(Post)

    if n.respond_to?(:likeable)
      likeable = n.likeable
      return likeable if likeable.is_a?(Post)
      return likeable.post if likeable.respond_to?(:post) && likeable.post.is_a?(Post)
    end

    nil
  end

  # Who "said" it: a post written as a page speaks as the page, not as the
  # member who wrote it.
  def voice_name
    post = notifiable if notifiable.is_a?(Post)
    return post.page.name if post&.page && (actor_id.nil? || post.user_id == actor_id)

    actor&.display_name || "Someone"
  end

  # The page an alert is about (a Page, or a PageMembership's page).
  def page_name_for_alert
    page = notifiable.is_a?(Page) ? notifiable : notifiable.try(:page)
    page&.name.present? ? "“#{page.name}”" : "a page"
  end

  # "3 new people followed “Grace Chapel”": the one daily alert counts up
  # everyone who followed since it was made.
  def followers_alert_text
    page = notifiable
    return "Your page has a new follower" unless page.is_a?(Page)

    since = created_at || Time.current
    others = page.follows.where(created_at: (since - 1.second)..).where.not(user_id: actor_id).count
    name = actor&.display_name || "Someone"
    others.positive? ? "#{name} and #{others} #{others == 1 ? 'other' : 'others'} followed “#{page.name}”" : "#{name} followed “#{page.name}”"
  end

  # "in <circle name>" when the notifiable still has its circle, else fallback.
  def circle_name_suffix(fallback = "your circle")
    name = notifiable.respond_to?(:circle) ? notifiable.circle&.name : nil
    name.present? ? "“#{name}”" : fallback
  end

  # Class methods
  def self.mark_all_as_read!(user)
    user.notifications.unread.update_all(read_at: Time.current)
  end

  # The actor id to store for a notification about `post`: nil when the
  # actor is the hidden author of an anonymous breath, else unchanged.
  def self.anonymous_actor_id_for(post, actor_id)
    return actor_id unless post.is_a?(Post) && post.anonymous?

    actor_id == post.user_id ? nil : actor_id
  end

  private

  # Anonymous breaths must never unmask their author. Any notification about
  # an anonymous breath whose actor *is* that author (mentions, @everyone,
  # prayer answered, a quote, their own comment on it…) is stored with no
  # actor, so every copy — in-app, email, push — reads "Someone".
  # (Bulk insert_all paths call Notification.anonymous_actor_id_for directly.)
  def conceal_anonymous_author
    return if actor_id.nil?

    post = underlying_post
    self.actor = nil if post&.anonymous? && post.user_id == actor_id
  rescue StandardError
    nil
  end

  def deliver_email_notification
    return unless user.email_notifications_enabled?
    return if birthday? || skill_endorsed? || app_update? || rank_up? || bible_reminder? || page_new_follower? || page_mentioned? || feedback_request? || contact_shared? # a push and the alert are enough; no emails for these
    return if notifiable.is_a?(Message) && notifiable.quiet? # e.g. the welcome note, which has its own email

    NotificationMailer.with(notification: self).community_notification.deliver_later
  end

  # One chat notification per conversation: "Maria: See you at 7", or
  # "Maria sent you 3 messages" when several are waiting.
  def direct_message_text
    name = actor&.display_name || "Someone"
    conversation = notifiable.try(:conversation)
    waiting = conversation ? conversation.unread_count_for(user) : 1
    return "#{name} sent you #{waiting} messages" if waiting > 1

    preview = notifiable.try(:body).to_s.squish
    return "#{name}: #{preview.truncate(120)}" if preview.present? && preview != "[deleted]"
    return "#{name} sent you a GIF" if notifiable.try(:has_gif?) && !notifiable.try(:deleted?)

    "#{name} sent you a message"
  end

  def deliver_push_notification
    web    = WebPushConfig.configured? && user.push_subscriptions.exists?
    native = NativePushConfig.configured? && user.push_devices.deliverable.exists?
    return unless web || native
    return if page_new_follower? # counted up in the alerts list; no buzz per follower
    return if feedback_request? && !notifiable.try(:also_push?) # surveys buzz only when the admin asked

    PushNotificationJob.perform_later(self)
  end

  # Also called when a waiting chat notification is refreshed by a newer message.
  public :deliver_push_notification

  def not_between_blocked_members
    return if actor_id.blank? || user_id.blank? || actor_id == user_id
    return unless SOCIAL_TYPES.include?(notification_type.to_s)

    errors.add(:base, "blocked") if MessageBlock.between?(user_id, actor_id)
  end
end
