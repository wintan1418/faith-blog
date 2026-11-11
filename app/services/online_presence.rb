# frozen_string_literal: true

# Members another member can see as online right now: active, sharing their
# status (Settings → Privacy), not the viewer, and with no message block either
# way. People the viewer follows or is connected with come first.
class OnlinePresence
  LIMIT = 12

  attr_reader :viewer

  def initialize(viewer, limit: LIMIT)
    @viewer = viewer
    @limit = limit
  end

  def scope
    @scope ||= User.active.online.sharing_presence.where.not(id: [ viewer.id, *blocked_ids ])
  end

  def count
    @count ||= scope.count
  end

  def any? = count.positive?

  # Close brethren first (most recently seen), then everyone else.
  def users
    @users ||= begin
      close = with_avatars(scope.where(id: close_ids)).order(last_seen_at: :desc).limit(@limit).to_a
      rest = @limit - close.size
      others = rest.positive? ? with_avatars(scope.where.not(id: close_ids)).order(last_seen_at: :desc).limit(rest).to_a : []
      close + others
    end
  end

  private

  def with_avatars(relation) = relation.includes(profile: { avatar_attachment: :blob })

  def close_ids
    @close_ids ||= viewer.active_follows.pluck(:following_id) | viewer.connection_ids
  end

  def blocked_ids
    MessageBlock.where(blocker_id: viewer.id).pluck(:blocked_id) |
      MessageBlock.where(blocked_id: viewer.id).pluck(:blocker_id)
  end
end
