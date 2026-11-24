# frozen_string_literal: true

# A member's own recent searches, shown in the search box's dropdown. Only
# they see them, and they can clear them.
class RecentSearch < ApplicationRecord
  KEEP = 8

  belongs_to :user

  scope :latest, -> { order(searched_at: :desc) }

  def self.remember(user, text)
    query = SiteSearch::Query.normalize(text).first(120)
    return if user.nil? || query.blank?

    now = Time.current
    upsert({ user_id: user.id, query: query, searched_at: now }, unique_by: %i[user_id query], update_only: [ :searched_at ])
    stale = where(user_id: user.id).latest.offset(KEEP).pluck(:id)
    where(id: stale).delete_all if stale.any?
  rescue StandardError => e
    Rails.logger.warn("[search] recent search not saved: #{e.class}: #{e.message}")
    nil
  end

  def self.for(user, limit: 5)
    return none unless user

    where(user_id: user.id).latest.limit(limit)
  end
end
