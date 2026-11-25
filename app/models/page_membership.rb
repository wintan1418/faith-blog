# frozen_string_literal: true

# Someone who runs a page: the owner (exactly one), admins (edit the page and
# its people) and editors (post as the page). Owners invite admins and editors
# by username; the invite waits (pending) until they accept it.
class PageMembership < ApplicationRecord
  ROLE_LABELS = { "owner" => "Owner", "admin" => "Admin", "editor" => "Editor" }.freeze
  # Admins and editors a page may have (the owner aside).
  MAX_TEAM = 25

  enum :role, { owner: 0, admin: 1, editor: 2 }, validate: true
  enum :status, { pending: 0, active: 1 }, validate: true

  belongs_to :page
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :user_id, uniqueness: { scope: :page_id, message: "is already on this page's team" }
  validate :team_not_full, on: :create

  scope :invites_for, ->(user) { pending.where(user: user) }

  def role_label = ROLE_LABELS[role]

  def accept!
    update!(status: :active, accepted_at: Time.current)
  end

  private

  def team_not_full
    return if owner? || page.nil?

    errors.add(:base, "A page can have up to #{MAX_TEAM} admins and editors") if page.memberships.where.not(role: :owner).count >= MAX_TEAM
  end
end
