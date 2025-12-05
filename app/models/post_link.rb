# frozen_string_literal: true

class PostLink < ApplicationRecord
  belongs_to :source_post, class_name: 'Post'
  belongs_to :target_post, class_name: 'Post'

  enum :link_type, { 
    related: 'related',       # General related content
    reference: 'reference',   # References/cites another post
    continuation: 'continuation', # Part 2, sequel, etc.
    response: 'response'      # Response/reply to another post
  }, default: :related

  validates :source_post_id, uniqueness: { scope: :target_post_id, message: "already linked to this post" }
  validate :cannot_link_to_self

  scope :by_type, ->(type) { where(link_type: type) }

  def link_type_label
    case link_type
    when 'related' then '🔗 Related'
    when 'reference' then '📚 References'
    when 'continuation' then '📖 Continues from'
    when 'response' then '💬 In response to'
    else '🔗 Linked'
    end
  end

  private

  def cannot_link_to_self
    if source_post_id == target_post_id
      errors.add(:target_post_id, "cannot link a post to itself")
    end
  end
end

