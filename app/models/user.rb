# frozen_string_literal: true

class User < ApplicationRecord
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  # Enums
  enum :role, { member: 0, moderator: 1, admin: 2, super_admin: 3 }

  # Associations
  has_one :profile, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :announcements, dependent: :destroy

  validates :accent_color, inclusion: { in: -> (_) { AccentPalette.slugs } }, allow_blank: true
  has_many :game_attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :bookmarked_posts, through: :bookmarks, source: :post
  has_many :reshares, dependent: :destroy
  has_many :reshared_posts, through: :reshares, source: :post
  has_many :resources, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :reports, foreign_key: :reporter_id, dependent: :destroy
  has_many :moderation_logs, foreign_key: :moderator_id, dependent: :nullify
  has_one  :risk_profile, class_name: "UserRiskProfile", dependent: :destroy
  has_many :ai_moderation_reviews, dependent: :nullify
  has_many :prayer_intercessions, dependent: :destroy
  has_many :prayed_for_posts, through: :prayer_intercessions, source: :post
  has_many :user_reading_plans, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
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
                       format: { with: /\A[a-zA-Z0-9_]+\z/, message: "can only contain letters, numbers, and underscores" }

  # Callbacks
  after_create :create_profile
  after_create :create_brethren_card
  after_create :ensure_risk_profile
  after_create_commit :announce_join

  # Scopes
  scope :active, -> { where(active: true) }
  scope :verified, -> { where.not(verified_at: nil) }

  # Instance methods
  def display_name
    username
  end

  def self.from_google(auth)
    email = auth.info.email.to_s.downcase
    user = find_by(provider: auth.provider, uid: auth.uid) || find_by(email: email)

    user ||= new(email: email, username: unique_username_from(auth), password: Devise.friendly_token.first(32))
    user.provider = auth.provider
    user.uid = auth.uid
    user.password = Devise.friendly_token.first(32) if user.encrypted_password.blank?
    user.save!
    user
  end

  def admin_or_moderator?
    super_admin? || admin? || moderator?
  end

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive
  end

  def follow(user)
    return if self == user || following?(user)

    active_follows.create(following: user)
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
    likes.exists?(likeable: likeable)
  end

  # Online if we touched last_seen_at within the past minute. Touch is
  # done by ApplicationController on every authenticated request.
  def online?
    last_seen_at.present? && last_seen_at > 1.minute.ago
  end

  def last_seen_label
    return "Active now" if online?
    return "Last seen recently" if last_seen_at.blank?

    diff = Time.current - last_seen_at
    case diff
    when 0..(60)            then "Active now"
    when 60..(60 * 60)      then "Last seen #{(diff / 60).to_i}m ago"
    when (60 * 60)..(24 * 60 * 60)
      "Last seen #{(diff / 3600).to_i}h ago"
    when (24 * 60 * 60)..(7 * 24 * 60 * 60)
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

  def streak_label
    n = current_breath_streak.to_i
    return nil if n.zero?
    return "#{n} day streak" if n == 1
    "#{n} days streaking"
  end

  def has_reshared?(post)
    reshares.exists?(post: post)
  end

  def unread_notifications_count
    notifications.unread.count
  end

  def unread_conversations_count
    conversation_participants
      .joins("INNER JOIN messages ON messages.conversation_id = conversation_participants.conversation_id")
      .where.not(messages: { sender_id: id })
      .where("conversation_participants.last_read_at IS NULL OR messages.created_at > conversation_participants.last_read_at")
      .distinct
      .count(:conversation_id)
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

  def connections
    accepted_sent = sent_connection_requests.accepted.includes(:receiver).map(&:receiver)
    accepted_received = received_connection_requests.accepted.includes(:sender).map(&:sender)
    accepted_sent + accepted_received
  end

  def connections_count
    sent_connection_requests.accepted.count + received_connection_requests.accepted.count
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

  def announce_join
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
