# frozen_string_literal: true

# Every morning: one email to the admins about the day before (bots the
# sign-up guard stopped, new members, posts and messages). Only real failures
# (crashes, the health check, features that keep failing) still email at once.
class DailySummaryJob < ApplicationJob
  queue_as :default

  def perform(date = Date.yesterday)
    admins = ErrorAlert.recipients.to_a
    return if admins.empty?

    day = date.in_time_zone.all_day
    stats = {
      new_members: User.where(created_at: day).count,
      breaths: Post.where(status: :published, published_at: day).count,
      comments: Comment.where(created_at: day).count,
      messages: Message.where(created_at: day).count
    }
    AdminAlertMailer.daily_summary(emails: admins.map(&:email), date: date,
                                   bots: SignupGuard.blocked_on(date), stats: stats).deliver_now
  end
end
