# frozen_string_literal: true

# Seeds: points members earn for building each other up. Every award is a row
# in the seed_events ledger (unique per user, kind and source, so nothing pays
# twice) and users.seeds_total caches the sum.
#
# Every public method here is safe to call from a callback in the middle of a
# request: failures are logged and swallowed. Seeds must never cost anyone a
# comment, a reaction or a page.
module Seeds
  RULES = {
    "breath"            => { points: 10,  daily_cap: 10, label: "Publish a breath" },
    "comment"           => { points: 5,   daily_cap: 20, label: "Comment on a breath, or reply on yours" },
    "comment_received"  => { points: 2,   daily_cap: nil, label: "Someone comments on your breath" },
    "reaction_received" => { points: 1,   daily_cap: 50, label: "Someone reacts to your breath or comment" },
    "intercession"      => { points: 3,   daily_cap: 10, label: "Join someone's prayer chain" },
    "streak_7"          => { points: 20,  daily_cap: nil, label: "7-day breath streak" },
    "streak_30"         => { points: 50,  daily_cap: nil, label: "30-day breath streak" },
    "streak_100"        => { points: 100, daily_cap: nil, label: "100-day breath streak" },
    "badge"             => { points: 25,  daily_cap: nil, label: "Earn a badge" },
    "invite_joined"     => { points: 25,  daily_cap: 10, label: "A friend joins through your invite and posts" }
  }.freeze

  STREAK_BONUSES = { 7 => "streak_7", 30 => "streak_30", 100 => "streak_100" }.freeze

  # A comment has to say something to earn: "Amen" is lovely, but free.
  MIN_COMMENT_CHARS = 20

  # Admins and super admins keep their own seeds and rank, but stay off the
  # public boards so the community sees itself, not the staff.
  LEADERBOARD_EXCLUDE_STAFF = true
  STAFF_ROLES = %w[admin super_admin].freeze
  # Shown in a pinned "Founder" card above the board instead: visible, unranked.
  FOUNDER_ROLES = %w[super_admin].freeze

  module_function

  def points_for(kind) = RULES.fetch(kind.to_s)[:points]

  # ── Earning ───────────────────────────────────────────────────────────

  # A breath went live (published and approved). Also pays a streak bonus on
  # days 7, 30 and 100.
  # `streak_bumped`: this breath moved the streak on (the first of the day), so
  # a milestone streak pays its bonus once, not on every breath that day.
  def breath_published(post, streak_bumped: false, at: nil, notify: true)
    safely("breath #{post&.id}") do
      next unless post&.user_id && post.feed_visible?

      at ||= post.published_at || Time.current
      paid = award(user_id: post.user_id, kind: "breath", source: post, at: at, post: post,
                   anonymous: post.anonymous?, notify: notify)
      streak_bonus(post, at: at, notify: notify) if streak_bumped
      invite_joined(post.user_id, at: at, notify: notify)
      paid
    end
  end

  def streak_bonus(post, streak: nil, at: nil, notify: true)
    streak ||= User.where(id: post.user_id).pick(:current_breath_streak).to_i
    kind = STREAK_BONUSES[streak]
    return unless kind

    award(user_id: post.user_id, kind: kind, source: post, at: at || Time.current, post: post,
          anonymous: post.anonymous?, notify: notify)
  end

  # An approved comment: +5 to the commenter (on someone else's breath, with
  # real words) and +2 to the breath's author (once per commenter per breath).
  def comment_created(comment, at: nil, notify: true)
    safely("comment #{comment&.id}") do
      next unless comment&.user_id && comment.moderation_approved? && !comment.deleted?

      post = comment.post
      next unless post&.user_id
      own = post.user_id == comment.user_id
      next if !own && MessageBlock.between?(comment.user_id, post.user_id)

      at ||= comment.created_at || Time.current
      context = { post: post, comment_id: comment.id, actor_id: comment.user_id, at: at, notify: notify }
      invite_joined(comment.user_id, at: at, notify: notify) if substantial_comment?(comment)

      # On your own breath it only counts as a reply to someone who commented first.
      paid = nil
      if substantial_comment?(comment) && (!own || replying_on_own_breath?(post, comment))
        paid = award(user_id: comment.user_id, kind: "comment", source: comment, **context)
      end
      next paid if own

      already = SeedEvent.exists?(user_id: post.user_id, kind: "comment_received",
                                  post_id: post.id, actor_id: comment.user_id)
      unless already
        paid = award(user_id: post.user_id, kind: "comment_received", source: comment,
                     anonymous: post.anonymous?, **context) || paid
      end
      paid
    end
  end

  # Real words (20+ characters), or a GIF, picture or voice note.
  def substantial_comment?(comment)
    return true if comment.content.to_plain_text.to_s.squish.length >= MIN_COMMENT_CHARS
    return true if comment.respond_to?(:has_gif?) && comment.has_gif?

    comment.content&.body&.attachments.present?
  end

  def replying_on_own_breath?(post, comment)
    post.comments.where.not(user_id: comment.user_id)
        .where(created_at: ...(comment.created_at || Time.current)).exists?
  end

  # +1 to whoever wrote the breath or comment someone else reacted to.
  def reaction_created(like, at: nil, notify: true)
    safely("reaction #{like&.id}") do
      target = like&.likeable
      next unless like.user_id && (target.is_a?(Post) || target.is_a?(Comment))

      receiver_id = target.user_id
      next if receiver_id.nil? || receiver_id == like.user_id
      next if MessageBlock.between?(like.user_id, receiver_id)

      post = target.is_a?(Post) ? target : target.post
      # The masked author of an anonymous breath, on the breath or on their
      # own comments under it.
      anonymous = post&.anonymous? && post.user_id == receiver_id
      award(user_id: receiver_id, kind: "reaction_received", source: like, at: at || like.created_at || Time.current,
            post: post, comment_id: (target.id if target.is_a?(Comment)), actor_id: like.user_id,
            anonymous: anonymous, notify: notify)
    end
  end

  # +3 for standing in prayer with someone else.
  def intercession_created(intercession, at: nil, notify: true)
    safely("intercession #{intercession&.id}") do
      post = intercession&.post
      next unless post&.prayer? && intercession.user_id && post.user_id != intercession.user_id
      next if MessageBlock.between?(intercession.user_id, post.user_id)

      award(user_id: intercession.user_id, kind: "intercession", source: intercession,
            at: at || intercession.created_at || Time.current, post: post, actor_id: intercession.user_id,
            notify: notify)
    end
  end

  # +25 to whoever brought a member in (users.invited_by_id), once per member
  # and only when that member turns out to be real: an active account that
  # published a live breath or wrote an approved comment with real words.
  # Signing up alone pays nothing, so empty accounts can't be farmed; the
  # daily cap limits the rest. The new member is the source, so it pays once.
  def invite_joined(invitee_id, at: nil, notify: true)
    safely("invite_joined #{invitee_id}") do
      invitee = User.where(id: invitee_id, active: true).where.not(invited_by_id: nil).first
      next unless invitee && invitee.invited_by_id != invitee.id && !invitee.site_monitor?

      inviter_id = invitee.invited_by_id
      next unless User.where(id: inviter_id, active: true).exists?

      award(user_id: inviter_id, kind: "invite_joined", source: invitee, at: at || Time.current,
            actor_id: invitee.id, notify: notify)
    end
  end

  def badge_awarded(badge, at: nil, notify: true)
    safely("badge #{badge&.id}") do
      next unless badge&.user_id

      award(user_id: badge.user_id, kind: "badge", source: badge, at: at || badge.awarded_at || Time.current,
            notify: notify)
    end
  end

  # ── Reversals ─────────────────────────────────────────────────────────

  # A breath was deleted, held or blocked: its author loses what it earned
  # them (the breath itself, a streak bonus on it, comments and reactions it
  # received). Other people keep what they earned around it.
  def revoke_post(post_or_id, author_id: nil)
    safely("revoke post") do
      post_id = post_or_id.is_a?(Post) ? post_or_id.id : post_or_id
      author_id ||= post_or_id.is_a?(Post) ? post_or_id.user_id : Post.where(id: post_id).pick(:user_id)
      next unless post_id && author_id

      remove(SeedEvent.where(post_id: post_id, user_id: author_id))
    end
  end

  # A comment was deleted, held or blocked: the commenter's seeds, the
  # author's "received a comment" seeds and any reactions on it go.
  def revoke_comment(comment_or_id)
    safely("revoke comment") do
      comment_id = comment_or_id.is_a?(Comment) ? comment_or_id.id : comment_or_id
      remove(SeedEvent.where(comment_id: comment_id)) if comment_id
    end
  end

  # Whatever one record (a reaction, an intercession) paid out.
  def revoke_source(record)
    safely("revoke #{record.class.name}") do
      remove(SeedEvent.where(source_type: record.class.polymorphic_name, source_id: record.id))
    end
  end

  def recompute_totals!(user_ids)
    ids = Array(user_ids).compact.uniq
    return if ids.empty?

    User.where(id: ids).update_all(<<~SQL.squish)
      seeds_total = COALESCE((SELECT SUM(points) FROM seed_events WHERE seed_events.user_id = users.id), 0)
    SQL
  end

  # ── Internals ─────────────────────────────────────────────────────────

  def award(user_id:, kind:, source:, at:, post: nil, comment_id: nil, actor_id: nil, anonymous: false, notify: true)
    rule = RULES.fetch(kind)
    day = at.in_time_zone.to_date
    source_type = source.class.polymorphic_name
    before = after = nil

    SeedEvent.transaction do
      before = User.lock.where(id: user_id).pick(:seeds_total)
      next if before.nil?
      next if SeedEvent.exists?(user_id: user_id, kind: kind, source_type: source_type, source_id: source.id)
      next if rule[:daily_cap] && SeedEvent.where(user_id: user_id, kind: kind, created_on: day).count >= rule[:daily_cap]

      SeedEvent.create!(
        user_id: user_id, kind: kind, points: rule[:points], source_type: source_type, source_id: source.id,
        post_id: post&.id, room_id: post&.room_id, comment_id: comment_id, actor_id: actor_id,
        anonymous: anonymous, created_on: day, created_at: at
      )
      recompute_totals!(user_id)
      after = User.where(id: user_id).pick(:seeds_total)
    end
    return unless after

    note_for_viewer(user_id, after - before)
    rank_up!(user_id, after) if notify
    after - before
  rescue ActiveRecord::RecordNotUnique
    nil # raced with the same award elsewhere; it's paid once, which is the point
  end

  def remove(scope)
    user_ids = scope.distinct.pluck(:user_id)
    return if user_ids.empty?

    scope.delete_all
    recompute_totals!(user_ids)
  end

  # The signed-in member who just earned sees a "+5 seeds" toast.
  def note_for_viewer(user_id, points)
    return unless points.to_i.positive? && Current.user&.id == user_id

    Current.seeds_earned = Current.seeds_earned.to_i + points
  end

  # A new rank, reached for the first time: one notification, and the
  # celebration waits for the member's next page (seeds_rank_seen).
  def rank_up!(user_id, total)
    rank = Rank.for(total)
    claimed = User.where(id: user_id).where(seeds_rank_reached: ...rank.index)
                  .update_all(seeds_rank_reached: rank.index)
    return unless claimed == 1

    reached = SeedRankUp.create!(user_id: user_id, rank_index: rank.index)
    Notification.create(user_id: user_id, actor_id: user_id, notifiable: reached, notification_type: :rank_up)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def safely(what)
    yield
  rescue StandardError => e
    Rails.logger.error("[Seeds] #{what} failed: #{e.class}: #{e.message}")
    nil
  end
end
