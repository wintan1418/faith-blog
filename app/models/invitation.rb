# frozen_string_literal: true

class Invitation < ApplicationRecord
  belongs_to :inviter, class_name: "User"
  belongs_to :invited_user, class_name: "User", optional: true

  before_validation :normalize_email
  before_validation :ensure_token

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :inviter_id, message: "has already been invited by you" }
  validates :token, presence: true, uniqueness: true
  validate :cannot_invite_self
  validate :email_is_not_registered

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  def self.find_pending_by_token(token)
    pending.find_by(token: token.to_s)
  end

  def accepted?
    accepted_at.present?
  end

  def deliver!
    InvitationMailer.with(invitation: self).invite.deliver_later
    update!(last_sent_at: Time.current)
  end

  def accept!(user)
    update!(invited_user: user, accepted_at: Time.current)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def cannot_invite_self
    errors.add(:email, "is already your account email") if inviter&.email&.casecmp?(email)
  end

  def email_is_not_registered
    return if invited_user_id.present?

    errors.add(:email, "already belongs to a Brethreign account") if User.exists?(email: email)
  end
end
