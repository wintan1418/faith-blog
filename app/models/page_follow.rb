# frozen_string_literal: true

# A member following a page: the page's posts come into their Following feed.
# The page's managers hear about new followers at most once a day per page
# (one alert that counts them up), never one alert per follower.
class PageFollow < ApplicationRecord
  belongs_to :page, counter_cache: :followers_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :page_id }

  after_create_commit :tell_managers

  private

  def tell_managers
    page.managers.where.not(id: user_id).find_each do |manager|
      # One unread "new followers" alert per page per manager per day.
      next if Notification.where(user: manager, notifiable: page, notification_type: :page_new_follower, read_at: nil)
                          .where(created_at: 1.day.ago..).exists?

      Notification.create(user: manager, actor: user, notifiable: page, notification_type: :page_new_follower)
    end
  rescue StandardError => e
    Rails.logger.warn("[PageFollow] follower alert failed for page #{page_id}: #{e.class}: #{e.message}")
  end
end
