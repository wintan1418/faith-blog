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

  def has_bookmarked?(post)
    bookmarks.exists?(post: post)
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
end
