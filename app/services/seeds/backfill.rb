# frozen_string_literal: true

module Seeds
  # Pays seeds for activity from before Seeds existed, with the same rules and
  # daily caps as live earning (each day counted on the day it happened).
  # Idempotent: the ledger's uniqueness means a second run pays nothing new.
  # No notifications and no rank-up celebrations: members simply start at the
  # rank their history earned.
  class Backfill
    def initialize(io: $stdout)
      @io = io
    end

    def run
      Current.reset # never toast anyone from a backfill
      before = SeedEvent.count

      step("breaths") { breaths }
      step("streaks") { streaks }
      step("comments") { comments }
      step("reactions") { reactions }
      step("prayer chains") { intercessions }
      step("badges") { badges }
      settle_ranks

      added = SeedEvent.count - before
      say "Done: #{added} new ledger rows, #{SeedEvent.sum(:points)} seeds across #{User.where('seeds_total > 0').count} members."
      added
    end

    private

    def live_posts
      Post.published.where(published_at: ..Time.current)
    end

    def breaths
      live_posts.order(:published_at, :id).to_a.count do |post|
        Seeds.breath_published(post, at: post.published_at, notify: false)
      end
    end

    # Rebuild each member's streak runs from the days they breathed, and pay
    # the 7 / 30 / 100-day bonus on the breath that reached it.
    def streaks
      paid = 0
      live_posts.distinct.pluck(:user_id).each do |user_id|
        firsts = live_posts.where(user_id: user_id).order(:published_at).to_a
                           .group_by { |p| p.published_at.in_time_zone.to_date }
                           .transform_values(&:first)
        run = 0
        previous = nil
        firsts.keys.sort.each do |day|
          run = previous && day == previous + 1 ? run + 1 : 1
          previous = day
          next unless STREAK_BONUSES.key?(run)

          post = firsts[day]
          paid += 1 if Seeds.streak_bonus(post, streak: run, at: post.published_at, notify: false)
        end
      end
      paid
    end

    def comments
      Comment.active.moderation_visible.where(post_id: live_posts.select(:id))
             .includes(:post, :rich_text_content).find_each.sort_by { |c| [ c.created_at, c.id ] }
             .count { |comment| Seeds.comment_created(comment, at: comment.created_at, notify: false) }
    end

    def reactions
      Like.where(likeable_type: %w[Post Comment]).includes(:likeable).find_each.sort_by { |l| [ l.created_at, l.id ] }.count do |like|
        target = like.likeable
        live = case target
        when Post then target.feed_visible?
        when Comment then target.moderation_approved? && !target.deleted? && target.post&.feed_visible?
        end
        live && Seeds.reaction_created(like, at: like.created_at, notify: false)
      end
    end

    def intercessions
      PrayerIntercession.where(post_id: live_posts.select(:id)).includes(:post).order(:created_at, :id)
                        .to_a.count { |i| Seeds.intercession_created(i, at: i.created_at, notify: false) }
    end

    def badges
      UserBadge.order(:awarded_at, :id).to_a.count { |b| Seeds.badge_awarded(b, at: b.awarded_at, notify: false) }
    end

    # Totals are already current (every award recomputes). Mark each
    # member's rank as reached and seen, so nobody gets a pile of
    # celebrations for history.
    def settle_ranks
      Seeds.recompute_totals!(SeedEvent.distinct.pluck(:user_id))
      User.where("seeds_total > 0").find_each do |user|
        index = user.seeds_rank.index
        next if user.seeds_rank_reached >= index && user.seeds_rank_seen >= index

        user.update_columns(seeds_rank_reached: [ user.seeds_rank_reached, index ].max,
                            seeds_rank_seen: [ user.seeds_rank_seen, index ].max)
      end
    end

    def step(name)
      started = Time.current
      count = yield
      say "#{name}: #{count} paid (#{(Time.current - started).round(1)}s)"
    end

    def say(line) = @io&.puts("[seeds:backfill] #{line}")
  end
end
