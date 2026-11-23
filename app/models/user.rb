# frozen_string_literal: true

class User < ApplicationRecord
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :omniauthable, :lockable,
         omniauth_providers: [ :google_oauth2 ]

  # Enums
  enum :role, { member: 0, moderator: 1, admin: 2, super_admin: 3 }

  # Associations
  has_one :profile, dependent: :destroy
  has_many :suggestion_dismissals, dependent: :delete_all
  has_many :dismissed_as_suggestion, class_name: "SuggestionDismissal", foreign_key: :dismissed_user_id,
                                     dependent: :delete_all, inverse_of: :dismissed_user

  # Professional profile (LinkedIn-style)
  has_many :experiences, -> { ordered }, dependent: :destroy
  has_many :educations, -> { ordered }, dependent: :destroy
  has_many :certifications, -> { ordered }, dependent: :destroy
  has_many :languages, -> { ordered }, class_name: "UserLanguage", dependent: :destroy
  has_many :portfolio_items, -> { ordered }, dependent: :destroy
  has_many :skill_endorsements, dependent: :destroy # endorsements this member received
  has_many :given_endorsements, class_name: "SkillEndorsement", foreign_key: :endorser_id, dependent: :destroy, inverse_of: :endorser

  # One line under the name: the headline they wrote, or "Title at Organisation" from their current role.
  def professional_headline
    profile&.headline.presence ||
      experiences.find(&:current?)&.then { |role| "#{role.title} at #{role.organization}" }
  end

  def professional_profile?
    profile&.headline.present? || profile&.skills.present? || experiences.any? || educations.any?
  end
  has_many :posts, dependent: :destroy
  has_many :announcements, dependent: :destroy

  validates :accent_color, inclusion: { in: ->(_) { AccentPalette.slugs } }, allow_blank: true
  has_many :game_attempts, dependent: :destroy
  has_many :user_badges, dependent: :destroy
  has_many :seed_events, dependent: :delete_all
  has_many :seed_rank_ups, dependent: :destroy
  has_many :user_seen_quiz_questions, dependent: :delete_all
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :bookmarked_posts, through: :bookmarks, source: :post
  has_many :reshares, dependent: :destroy
  has_many :reshared_posts, through: :reshares, source: :post
  has_many :resources, dependent: :destroy
  has_many :notifications, dependent: :destroy
  # Notifications this user triggered for others: keep them, show "Someone".
  has_many :acted_notifications, class_name: "Notification", foreign_key: :actor_id, dependent: :nullify
  has_many :mentions, dependent: :delete_all
  has_many :reviewed_reports, class_name: "Report", foreign_key: :reviewed_by_id, dependent: :nullify
  has_many :approved_resources, class_name: "Resource", foreign_key: :approved_by_id, dependent: :nullify
  has_many :sent_broadcasts, class_name: "Broadcast", foreign_key: :sender_id, dependent: :nullify
  has_many :office_conversations, dependent: :destroy
  has_many :reports, foreign_key: :reporter_id, dependent: :destroy
  has_many :moderation_logs, foreign_key: :moderator_id, dependent: :nullify
  has_one  :risk_profile, class_name: "UserRiskProfile", dependent: :destroy
  has_many :ai_moderation_reviews, dependent: :nullify
  has_many :prayer_intercessions, dependent: :destroy
  has_many :prayed_for_posts, through: :prayer_intercessions, source: :post
  has_many :circle_memberships, dependent: :destroy
  has_many :circles, through: :circle_memberships
  has_many :owned_circles, class_name: "Circle", foreign_key: :owner_id, dependent: :destroy
  has_many :circle_breaths, dependent: :destroy
  has_many :circle_prayers, dependent: :destroy
  has_many :circle_prayer_amens, dependent: :destroy
  has_many :user_reading_plans, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  # Phones running the iOS / Android apps
  has_many :push_devices, class_name: "ApplicationPushDevice", as: :owner, dependent: :destroy
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id, dependent: :destroy
  has_many :message_blocks, foreign_key: :blocker_id, dependent: :destroy
  has_many :blocked_message_users, through: :message_blocks, source: :blocked
  has_many :message_blocks_against, class_name: "MessageBlock", foreign_key: :blocked_id, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id, dependent: :destroy
  has_many :accepted_invitations, class_name: "Invitation", foreign_key: :invited_user_id, dependent: :nullify

  # Room memberships
  has_many :room_memberships, dependent: :destroy
  has_many :rooms, through: :room_memberships

  # Brethren Card & Connection Requests
  has_one :brethren_card, dependent: :destroy
  has_many :sent_connection_requests, class_name: "ConnectionRequest", foreign_key: :sender_id, dependent: :destroy
  has_many :received_connection_requests, class_name: "ConnectionRequest", foreign_key: :receiver_id, dependent: :destroy

  # Following system
  has_many :active_follows, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :passive_follows, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  has_many :following, through: :active_follows, source: :following
  has_many :followers, through: :passive_follows, source: :follower

  # Validations
  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       length: { minimum: 3, maximum: 30 },
                       format: { with: /\A[a-zA-Z0-9_]+\z/,
                                 message: "may only use letters, numbers, or underscores — no spaces, hyphens, or punctuation" }

  # Callbacks
  after_create :create_profile
  after_create :create_brethren_card
  after_create :ensure_risk_profile
  after_create_commit :announce_join
  after_create_commit :send_welcome_note
  after_create_commit :accept_pending_invitations

  # Scopes
  # Members (the site health check's account never appears in member lists).
  scope :active, -> { where(active: true).where.not(email: SiteHealthCheck::EMAIL) }
  scope :verified, -> { where.not(verified_at: nil) }

  # Member search. Usernames are public handles, so they always match; bio,
  # location and faith background only match on public profiles (a private
  # profile's details must not be discoverable by probing search). Email is
  # never searchable — that would be an address-confirmation oracle.
  def self.member_search(query)
    pattern = "%#{sanitize_sql_like(query.to_s)}%"
    left_joins(:profile).where(
      "users.username ILIKE :q OR (COALESCE(profiles.public_profile, TRUE) AND " \
      "(profiles.bio ILIKE :q OR profiles.location ILIKE :q OR profiles.faith_background ILIKE :q))",
      q: pattern
    )
  end

  # Instance methods
  def display_name
    username
  end

  OAUTH_PROVIDER_NAMES = { "google_oauth2" => "Google", "apple" => "Apple" }.freeze

  # Set when the app (not the member) assigns a random password — OAuth
  # sign-ups and account linking — so password_chosen_at stays NULL.
  attr_accessor :password_generated

  before_save :track_password_chosen, if: :will_save_change_to_encrypted_password?

  # The member knows a password they picked themselves (and so can be asked
  # for it before changing email / password).
  def password_known? = password_chosen_at.present?

  def oauth_provider_name = OAUTH_PROVIDER_NAMES.fetch(provider.to_s, provider.to_s.titleize)

  # Also used for Sign in with Apple (provider "apple").
  #
  # Emails on password sign-ups are never confirmed, so anyone could have
  # registered someone else's address first ("pre-account hijack"). When a
  # Google / Apple sign-in — which proves the person owns the address — links
  # to an existing password account for the first time, the old password is
  # replaced with a random one (which also signs out every other session) and
  # the member is emailed how to set a new one. Whoever registered the address
  # earlier can no longer get in. Linking only happens on a verified email.
  def self.from_google(auth)
    email = auth.info.email.to_s.downcase
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    user = find_by(email: email)
    return create_from_oauth!(auth, email) unless user

    unless oauth_email_verified?(auth)
      user = new(email: email)
      user.errors.add(:email, "isn't verified with #{OAUTH_PROVIDER_NAMES.fetch(auth.provider.to_s, 'your provider')}, so it can't be linked to an existing account")
      raise ActiveRecord::RecordInvalid, user
    end

    first_link = user.provider.blank?
    user.provider = auth.provider
    user.uid = auth.uid
    if first_link || user.encrypted_password.blank?
      user.password = Devise.friendly_token.first(32)
      user.password_generated = true
      user.skip_password_change_notification!
      user.failed_attempts = 0
      user.locked_at = nil
      user.unlock_token = nil
    end
    user.save!
    AccountSecurityMailer.with(user: user, provider: auth.provider.to_s).linked_to_provider.deliver_later if first_link
    user
  end

  def self.create_from_oauth!(auth, email)
    user = new(email: email, username: unique_username_from(auth), password: Devise.friendly_token.first(32),
               provider: auth.provider, uid: auth.uid)
    user.password_generated = true
    user.save!
    user
  end

  # Native Google / Apple callers verify email_verified before calling us (and
  # build an auth hash with no extra). The web Google callback carries Google's
  # own flag in extra.raw_info / extra.id_info.
  def self.oauth_email_verified?(auth)
    extra = auth.respond_to?(:extra) ? auth.extra : nil
    return true if extra.blank?

    flag = extra.dig("raw_info", "email_verified")
    flag = extra.dig("id_info", "email_verified") if flag.nil?
    flag.nil? || [ true, "true" ].include?(flag)
  end

  # People this user has blocked, or who blocked them (a MessageBlock either
  # way): their breaths, reposts and comments are hidden from each other.
  FEED_SEEN_THROTTLE = 1.minute

  # Remember that they looked at the top of the feed (drives the New posts
  # pill and the "New" dots). At most one write a minute, and never backwards.
  def mark_feed_seen!(at = Time.current)
    return false if feed_seen_at && feed_seen_at > at - FEED_SEEN_THROTTLE

    update_column(:feed_seen_at, at)
    true
  end

  def blocked_user_ids
    @blocked_user_ids ||= MessageBlock.where(blocker_id: id).pluck(:blocked_id) |
                          MessageBlock.where(blocked_id: id).pluck(:blocker_id)
  end

  # One query per request for "have I blocked them?" (the feed asks once per post).
  def blocking?(other)
    other.present? && blocking_ids.include?(other.id)
  end

  def blocking_ids
    @blocking_ids ||= MessageBlock.where(blocker_id: id).pluck(:blocked_id).to_set
  end

  def reload(*)
    @blocking_ids = @blocked_user_ids = nil
    super
  end

  def admin_or_moderator?
    super_admin? || admin? || moderator?
  end

  # Strictly higher role than `other` (and never yourself).
  def outranks?(other)
    other.present? && other != self && self.class.roles.fetch(role) > self.class.roles.fetch(other.role)
  end

  # Trust threshold for skipping the AI moderation gate on new breaths.
  TRUSTED_BREATHER_POSTS = 20

  # A proven author: staff, or a clean track record — enough approved
  # breaths, a clear risk profile, and nothing the AI or a moderator has
  # flagged in the last 90 days. Trusted authors publish without an AI
  # call; everyone else keeps the full gate.
  def trusted_breather?
    return true if admin_or_moderator?
    return false unless risk_profile&.clear?
    return false if posts.where(moderation_status: :approved).count < TRUSTED_BREATHER_POSTS

    AiModerationReview.where(user_id: id, status: %i[flagged actioned])
                      .where(reviewed_at: 90.days.ago..)
                      .none?
  end

  # Only the super admin may see who wrote an anonymous post.
  def can_unmask_anonymous? = super_admin?

  # The account the site health check signs in as (SiteHealthCheck).
  def site_monitor? = email == SiteHealthCheck::EMAIL

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive
  end

  # The new Follow, or nil when it couldn't be made (yourself, already
  # following, or a block between you).
  def follow(user)
    return if self == user || following?(user)

    follow = active_follows.create(following: user)
    follow if follow.persisted?
  end

  def unfollow(user)
    active_follows.find_by(following: user)&.destroy
  end

  def following?(user)
    following.include?(user)
  end

  def followers_count
    followers.count
  end

  def following_count
    following.count
  end

  def has_liked?(likeable)
    # Feed cards preload the viewer's own like (Post#viewer_like, keyed on
    # Current.user); use it instead of a query per card.
    if Current.user&.id == id && likeable.class.reflect_on_association(:viewer_like) &&
       likeable.association(:viewer_like).loaded?
      return likeable.viewer_like.present?
    end
    likes.exists?(likeable: likeable)
  end

  # "Online" = seen within this window. The signed-in layout pings every 45s
  # while the page is visible (PresenceController), so two minutes covers one
  # missed beat plus network slack. Page loads also touch last_seen_at.
  ONLINE_WINDOW = 2.minutes

  scope :online, -> { where(last_seen_at: ONLINE_WINDOW.ago..) }
  # Members who let others see when they're online (Settings → Privacy).
  scope :sharing_presence, -> { where(show_online_status: true) }

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  # What other members may see: online only if they share their status.
  def visible_online?
    show_online_status? && online?
  end

  # "Active now" / "Last seen 5m ago", or nil when the member hides it.
  def presence_label
    last_seen_label if show_online_status?
  end

  def last_seen_label
    return "Active now" if online?
    return "Last seen recently" if last_seen_at.blank?

    diff = Time.current - last_seen_at
    case diff
    when 0...(60 * 60)      then "Last seen #{[ (diff / 60).to_i, 1 ].max}m ago"
    when (60 * 60)...(24 * 60 * 60)
      "Last seen #{(diff / 3600).to_i}h ago"
    when (24 * 60 * 60)...(7 * 24 * 60 * 60)
      "Last seen #{(diff / 86_400).to_i}d ago"
    else
      "Last seen #{last_seen_at.strftime("%b %-d")}"
    end
  end

  def has_bookmarked?(post)
    bookmarks.exists?(post: post)
  end

  # Update breath streak after a published post lands.
  # Today already counted? Skip. Yesterday? Increment. Older? Reset to 1.
  # Truthy only when this call moved the streak (Seeds pays streak bonuses then).
  def bump_breath_streak!
    today = Date.current
    return if streak_updated_on == today

    new_current = if streak_updated_on == today - 1
                    current_breath_streak.to_i + 1
    else
                    1
    end
    new_longest = [ longest_breath_streak.to_i, new_current ].max

    update_columns(
      current_breath_streak: new_current,
      longest_breath_streak: new_longest,
      streak_updated_on: today
    )
  end

  # Seeds: the member's rank comes from their total.
  def seeds_rank = Seeds::Rank.for(seeds_total)

  def seeds_this_week
    seed_events.since(Date.current.beginning_of_week).sum(:points)
  end

  # A rank reached whose celebration hasn't been shown yet.
  def rank_up_pending?
    seeds_rank_reached.to_i > seeds_rank_seen.to_i
  end

  def streak_label
    n = current_breath_streak.to_i
    return nil if n.zero?
    return "#{n} day streak" if n == 1
    "#{n} days streaking"
  end

  def has_reshared?(post)
    reshares.exists?(post: post)
  end

  # Alerts badge: activity only (messages are counted on the Inbox).
  def unread_notifications_count
    # Memoized: the navbar, layout and app markers ask several times per page.
    @unread_notifications_count ||= notifications.activity.unread.count
  end

  UNREAD_CONVERSATIONS_CAP = 100

  # Conversations with a message newer than my last read — counted the same
  # way as the inbox (not archived, deleted messages ignored) and capped:
  # badges show "99+" past 99, so there's no need to count further.
  def unread_conversations_count
    @unread_conversations_count ||= begin
      unread = conversation_participants.active
        .joins("INNER JOIN messages ON messages.conversation_id = conversation_participants.conversation_id")
        .where(messages: { deleted_at: nil })
        .where.not(messages: { sender_id: id })
        .where("conversation_participants.last_read_at IS NULL OR messages.created_at > conversation_participants.last_read_at")
        .distinct
        .select("conversation_participants.conversation_id")
        .limit(UNREAD_CONVERSATIONS_CAP)
      ConversationParticipant.from(unread, :unread).count
    end
  end

  # Push fresh unread counts to this member's open pages (navbar badges and the
  # count the apps read for their tab badges), so they change without a refresh.
  def broadcast_unread_counts
    fresh = User.find(id) # the counts above are memoized per instance
    Turbo::StreamsChannel.broadcast_replace_to(
      [ self, :badges ], target: "unread_counts", partial: "shared/unread_counts",
      locals: { messages: fresh.unread_conversations_count, notifications: fresh.unread_notifications_count }
    )
  rescue StandardError => e
    Rails.logger.warn("[User##{id}] unread count broadcast failed: #{e.class}: #{e.message}")
  end

  def connected_with?(user)
    ConnectionRequest.connected?(self, user)
  end

  def blocked_messages_with?(user)
    MessageBlock.between?(self, user)
  end

  def blocked_message_user?(user)
    message_blocks.exists?(blocked: user)
  end

  def connection_with(user)
    ConnectionRequest.between(self, user)
  end

  def pending_connection_from?(user)
    received_connection_requests.pending.exists?(sender: user)
  end

  def has_sent_connection_to?(user)
    sent_connection_requests.exists?(receiver: user)
  end

  # Ids of accepted connections, without loading the users.
  validate :username_is_clean, if: :will_save_change_to_username?

  def username_is_clean
    errors.add(:username, "isn't allowed. Please choose another") if CleanLanguage.offensive?(username.to_s.tr("_", " "))
  end

  validate :email_not_disposable, on: :create

  def email_not_disposable
    errors.add(:email, "from a throwaway email service can't be used. Please use your personal email") if DisposableEmail.disposable?(email)
  end

  def track_password_chosen
    self.password_chosen_at = password_generated ? nil : Time.current
    self.password_generated = false
  end

  # Cards this person closed, remembered across devices ("join-12", "release-3", "onboard-feed").
  DISMISSED_CARDS_KEPT = 300
  DISMISSAL_KEY = /\A[a-z0-9_-]{1,60}\z/

  def self.dismissal_key(raw) = raw.to_s.delete_prefix("fc:").downcase.presence&.then { |k| k if k.match?(DISMISSAL_KEY) }

  def card_dismissed?(key) = dismissed_cards.include?(User.dismissal_key(key))

  def dismiss_card!(key)
    key = User.dismissal_key(key)
    return false unless key
    return true if dismissed_cards.include?(key)

    update_column(:dismissed_cards, (dismissed_cards + [ key ]).last(DISMISSED_CARDS_KEPT))
  end

  def connection_ids
    sent_connection_requests.accepted.pluck(:receiver_id) | received_connection_requests.accepted.pluck(:sender_id)
  end

  # Connections celebrating a birthday today (who chose to share it).
  def brethren_birthdays_today
    User.joins(:profile).includes(profile: { avatar_attachment: :blob })
        .where(id: connection_ids, profiles: { show_birthday: true })
        .merge(Profile.birthday_on(Profile.today_for_birthdays))
        .limit(5)
  end

  def connections
    accepted_sent = sent_connection_requests.accepted.includes(:receiver).map(&:receiver)
    accepted_received = received_connection_requests.accepted.includes(:sender).map(&:sender)
    accepted_sent + accepted_received
  end

  def connections_count
    sent_connection_requests.accepted.count + received_connection_requests.accepted.count
  end

  # Number of incoming connection requests waiting on this user's reply.
  # Used by the navbar badge.
  def pending_connection_requests_count
    @pending_connection_requests_count ||= received_connection_requests.pending.count
  end

  private

  def self.unique_username_from(auth)
    base = auth.info.name.presence || auth.info.email.to_s.split("@").first || "brethren"
    username = base.parameterize(separator: "_").gsub(/[^a-zA-Z0-9_]/, "").presence || "brethren"
    username = username.first(24)
    candidate = username
    suffix = 2

    while exists?(username: candidate)
      candidate = "#{username.first(24)}_#{suffix}"
      suffix += 1
    end

    candidate
  end

  def create_profile
    build_profile.save
  end

  def create_brethren_card
    build_brethren_card.save(validate: false)
  end

  def ensure_risk_profile
    build_risk_profile.save unless risk_profile
  end

  # Anyone who invited this email sees "Accepted", however the person
  # signed up: Google, the app, or later without the invite link.
  def accept_pending_invitations
    Invitation.pending.where(email: email.to_s.strip.downcase)
              .update_all(invited_user_id: id, accepted_at: Time.current, updated_at: Time.current)
  end

  def send_welcome_note
    return if site_monitor?
    WelcomeNoteJob.perform_later(self)
  rescue StandardError => e
    Rails.logger.warn("[User##{id}] welcome note failed: #{e.class}: #{e.message}")
  end

  def announce_join
    return if site_monitor?
    Announcement.create(
      kind: :new_member,
      user: self,
      title: "#{username} just joined Brethreign",
      published_at: Time.current,
      expires_at: 14.days.from_now
    )
  rescue StandardError => e
    Rails.logger.warn("[User##{id}] announce_join failed: #{e.class}: #{e.message}")
  end
end
