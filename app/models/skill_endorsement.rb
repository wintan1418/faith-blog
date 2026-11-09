# frozen_string_literal: true

# A connection vouching for one of a member's skills ("+ Endorse"). One per
# person per skill; only people who are connected can endorse each other.
class SkillEndorsement < ApplicationRecord
  DAILY_LIMIT = 60

  belongs_to :user
  belongs_to :endorser, class_name: "User"
  has_many :notifications, as: :notifiable, dependent: :destroy

  before_validation { self.skill_key = self.class.key_for(skill) }

  validates :skill, presence: true, length: { maximum: 40 }
  validates :skill_key, uniqueness: { scope: %i[user_id endorser_id] }
  validate :not_yourself
  validate :connected, on: :create
  validate :skill_on_profile, on: :create
  validate :within_daily_limit, on: :create

  after_create_commit :notify

  def self.key_for(skill) = skill.to_s.squish.downcase.first(40)

  private

  def not_yourself
    errors.add(:base, "You can't endorse yourself") if user_id.present? && user_id == endorser_id
  end

  def connected
    return if user.nil? || endorser.nil?

    errors.add(:base, "Connect first to endorse skills") unless endorser.connection_with(user)&.accepted?
  end

  def skill_on_profile
    match = user&.profile&.skills.to_a.find { |s| self.class.key_for(s) == skill_key }
    match ? self.skill = match : errors.add(:skill, "isn't on their profile")
  end

  def within_daily_limit
    return if endorser.nil?

    today = self.class.where(endorser: endorser).where(created_at: Time.current.all_day).count
    errors.add(:base, "That's a lot of endorsements for one day. Try again tomorrow.") if today >= DAILY_LIMIT
  end

  def notify
    Notification.create(user: user, actor: endorser, notifiable: self, notification_type: :skill_endorsed)
  end
end
