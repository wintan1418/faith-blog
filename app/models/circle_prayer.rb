# frozen_string_literal: true

# An entry on a Prayer Circle's shared prayer list. Members tap "🙏 Prayed"
# (CirclePrayerAmen) to say they carried it; the one who asked — or the
# circle owner — marks it answered.
class CirclePrayer < ApplicationRecord
  belongs_to :circle
  belongs_to :user

  has_many :amens, class_name: "CirclePrayerAmen", dependent: :destroy

  enum :status, { open: 0, answered: 1 }, prefix: :prayer

  validates :title, presence: true, length: { maximum: 160 }
  validates :details, length: { maximum: 1_000 }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :notify_circle_of_request

  def prayed_by?(user)
    return false unless user

    amens.exists?(user_id: user.id)
  end

  def mark_answered!(by:)
    update!(status: :answered, answered_at: Time.current)
    circle.members.where.not(id: by.id).find_each do |member|
      Notification.create!(
        user: member,
        actor: by,
        notifiable: self,
        notification_type: :circle_prayer_answered
      )
    rescue StandardError => e
      Rails.logger.error("[CirclePrayer] answered notify failed for user #{member.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def notify_circle_of_request
    circle.members.where.not(id: user_id).find_each do |member|
      Notification.create!(
        user: member,
        actor: user,
        notifiable: self,
        notification_type: :circle_prayer
      )
    rescue StandardError => e
      Rails.logger.error("[CirclePrayer] notify failed for user #{member.id}: #{e.class}: #{e.message}")
    end
  end
end
