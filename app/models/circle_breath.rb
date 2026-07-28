# frozen_string_literal: true

# A breath inside a Prayer Circle's private stream. Plain text — the circle
# is a quiet room, not a stage.
class CircleBreath < ApplicationRecord
  belongs_to :circle
  belongs_to :user

  validates :body, presence: true, length: { maximum: 2_000 }

  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :notify_circle

  private

  # Circles are small by nature (a cell group, a family) — direct fanout.
  def notify_circle
    circle.members.where.not(id: user_id).find_each do |member|
      Notification.create!(
        user: member,
        actor: user,
        notifiable: self,
        notification_type: :circle_breath
      )
    rescue StandardError => e
      Rails.logger.error("[CircleBreath] notify failed for user #{member.id}: #{e.class}: #{e.message}")
    end
  end
end
