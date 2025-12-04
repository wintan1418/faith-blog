# frozen_string_literal: true

class Comment < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :post, counter_cache: true
  belongs_to :parent_comment, class_name: "Comment", optional: true, counter_cache: :replies_count
  has_many :replies, class_name: "Comment", foreign_key: :parent_comment_id, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  # Validations
  validates :content, presence: true, length: { minimum: 1, maximum: 2000 }

  # Scopes
  scope :root_comments, -> { where(parent_comment_id: nil) }
  scope :active, -> { where(deleted_at: nil) }
  scope :flagged, -> { where(flagged: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }

  # Instance methods
  def soft_delete!
    update(deleted_at: Time.current, content: "[This comment has been deleted]")
  end

  def deleted?
    deleted_at.present?
  end

  def edited?
    edited_at.present?
  end

  def mark_as_edited!
    update(edited_at: Time.current)
  end

  def depth
    parent_comment_id.nil? ? 0 : parent_comment.depth + 1
  end

  def root_comment?
    parent_comment_id.nil?
  end

  def reply?
    parent_comment_id.present?
  end
end

