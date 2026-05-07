# frozen_string_literal: true

class UserReadingPlan < ApplicationRecord
  belongs_to :user

  validates :plan_slug, presence: true, uniqueness: { scope: :user_id }

  def plan
    ReadingPlan.find(plan_slug)
  end

  def today_reading
    plan&.day(current_day)
  end

  def days_total
    plan&.days&.size || 0
  end

  def progress_percent
    total = days_total
    return 0 if total.zero?

    [ ((current_day - 1).to_f / total * 100).round, 100 ].min
  end

  def can_check_in_today?
    !completed && last_completed_on != Date.current
  end

  def check_in!
    return if completed

    today = Date.current
    return if last_completed_on == today

    next_day = current_day + 1
    if next_day > days_total
      update!(last_completed_on: today, completed: true)
    else
      update!(last_completed_on: today, current_day: next_day)
    end
  end
end
