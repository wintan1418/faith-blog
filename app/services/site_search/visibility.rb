# frozen_string_literal: true

module SiteSearch
  # What a searcher may find: exactly what they could reach by browsing.
  #
  # Breaths (everyone):
  #   * live: published, publish time arrived, moderation-approved, and not
  #     held by an open high-severity AI review (Post#held_for_review?)
  #   * by an active member (suspended / deactivated authors are gone)
  #   * not by someone they blocked or who blocked them (feed rule)
  #   * not in a private room unless they're a member or staff (Room#accessible_by?)
  # Signed-out visitors additionally only get what's public to search engines
  # and scripture pages: no anonymous breaths, no prayer requests, nothing in
  # prayer or struggles rooms (Post.scripture_discussable).
  #
  # Anonymous breaths are found by their words only: the author's name is
  # never in their vector, `from:` never matches them, and results never
  # show who wrote them.
  #
  # Replies count toward a breath only when they're visible on its page:
  # not deleted, approved, by an active member nobody in the pair has blocked.
  class Visibility
    attr_reader :viewer

    def initialize(viewer)
      @viewer = viewer
    end

    def guest? = viewer.nil?

    def staff?
      viewer.respond_to?(:admin_or_moderator?) && viewer.admin_or_moderator?
    end

    def blocked_ids
      @blocked_ids ||= guest? ? [] : viewer.blocked_user_ids.map(&:to_i)
    end

    # Rooms whose breaths this viewer can't see.
    def hidden_room_ids
      @hidden_room_ids ||= begin
        hidden = staff? ? Room.none : Room.where(is_public: false)
        hidden = hidden.where.not(id: viewer.room_memberships.select(:room_id)) if viewer && !staff?
        hidden = hidden.or(Room.where(room_type: %i[prayers struggles])) if guest?
        hidden.pluck(:id)
      end
    end

    def room_visible?(room)
      room && !hidden_room_ids.include?(room.id)
    end

    def rooms_scope
      hidden_room_ids.any? ? Room.where.not(id: hidden_room_ids) : Room.all
    end

    # SQL condition on `alias` (a posts row).
    def posts_sql(alias_name = "p")
      a = alias_name
      parts = [
        "#{a}.status = 1", "#{a}.moderation_status = 0", "#{a}.published_at <= statement_timestamp()",
        exclude_users_sql("#{a}.user_id", inactive_user_ids),
        "NOT EXISTS (SELECT 1 FROM ai_moderation_reviews amr WHERE amr.reviewable_id = #{a}.id " \
        "AND amr.reviewable_type = 'Post' AND amr.severity = 'high' AND amr.status NOT IN (1, 4))"
      ]
      parts << exclude_users_sql("#{a}.user_id", blocked_ids) if blocked_ids.any?
      parts << "(#{a}.room_id IS NULL OR #{a}.room_id <> ALL('{#{hidden_room_ids.join(',')}}'::bigint[]))" if hidden_room_ids.any?
      parts += [ "NOT #{a}.anonymous", "#{a}.prayer_status = 0" ] if guest?
      parts.join(" AND ")
    end

    def comments_sql(alias_name = "c")
      a = alias_name
      parts = [ "#{a}.deleted_at IS NULL", "#{a}.moderation_status = 0", exclude_users_sql("#{a}.user_id", inactive_user_ids) ]
      parts << exclude_users_sql("#{a}.user_id", blocked_ids) if blocked_ids.any?
      parts.join(" AND ")
    end

    # Members search finds: active, not blocked either way.
    def users_scope
      scope = User.active
      blocked_ids.any? ? scope.where.not(id: blocked_ids) : scope
    end

    private

    # Suspended members, plus the site health check's account (User.active).
    # A literal list (one indexed lookup per search) rather than a subquery,
    # so the planner can estimate how many rows it removes.
    def inactive_user_ids
      @inactive_user_ids ||= User.where(active: false).or(User.where(email: SiteHealthCheck::EMAIL)).pluck(:id)
    end

    def exclude_users_sql(column, ids)
      ids.empty? ? "TRUE" : "#{column} <> ALL('{#{ids.map(&:to_i).join(',')}}'::bigint[])"
    end
  end
end
