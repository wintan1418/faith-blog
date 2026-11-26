# frozen_string_literal: true

# "Your walk": the numbers shown in the feed's left rail on computers, the
# strip at the top of the feed on phones and the /walk page.
module WalkHelper
  # Prayer chains joined plus "Praying" taps on requests, this week.
  def walk_prayed_this_week(user)
    week = (1.week.ago..)
    user.prayer_intercessions.where(created_at: week).count +
      user.likes.where(reaction_type: :praying, created_at: week).count
  end

  # "3 days", or "Start" before the first one.
  def walk_days(count)
    count.to_i.positive? ? pluralize(count, "day") : "Start"
  end

  # Where "Prayed this week" leads: the community prayer room, else circles.
  def walk_prayer_path(prayer_room = nil)
    prayer_room ? room_path(prayer_room) : circles_path
  end
end
