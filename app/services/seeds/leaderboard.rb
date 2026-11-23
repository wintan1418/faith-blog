# frozen_string_literal: true

module Seeds
  # Public seed boards: this week, all time, or within one room. Counted from
  # the ledger, leaving out seeds earned on anonymous breaths (so no board can
  # hint at who wrote one) and, by default, the staff.
  class Leaderboard
    Row = Data.define(:position, :user, :seeds) do
      def rank = user.seeds_rank
    end

    PERIODS = %w[week all room].freeze

    attr_reader :period, :room

    def initialize(period: "week", room: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : "week"
      @room = room
    end

    def self.week_start = Date.current.beginning_of_week

    def top(limit = 20)
      totals = ranked_totals.limit(limit).to_a
      users = User.where(id: totals.map(&:user_id)).includes(profile: { avatar_attachment: :blob }).index_by(&:id)
      totals.each_with_index.filter_map do |row, i|
        user = users[row.user_id]
        Row.new(position: i + 1, user: user, seeds: row.seeds.to_i) if user
      end
    end

    # The viewer's own line, even when they're far down (or, as staff, not on
    # the public board at all: then position is nil).
    def position_of(user)
      return nil unless user

      seeds = events.where(user_id: user.id).sum(:points).to_i
      return Row.new(position: nil, user: user, seeds: seeds) unless eligible_users.exists?(id: user.id)
      return Row.new(position: nil, user: user, seeds: 0) if seeds.zero?

      ahead = SeedEvent.from(ranked_totals, :board).where("board.seeds > ?", seeds).count
      Row.new(position: ahead + 1, user: user, seeds: seeds)
    end

    # The founder's pinned card: their seeds for this period, with no position,
    # so the numbered places belong to the community.
    def founders
      return [] unless Seeds::LEADERBOARD_EXCLUDE_STAFF

      ids = User.active.where(role: Seeds::FOUNDER_ROLES).select(:id)
      totals = events.where(user_id: ids).group(:user_id).sum(:points).select { |_, seeds| seeds.positive? }
      User.where(id: totals.keys).includes(profile: { avatar_attachment: :blob })
          .map { |user| Row.new(position: nil, user: user, seeds: totals[user.id].to_i) }
          .sort_by { -it.seeds }
    end

    def ranked_totals
      events.where(user_id: eligible_users.select(:id))
            .group(:user_id)
            .select("seed_events.user_id, SUM(seed_events.points) AS seeds, MIN(seed_events.created_at) AS first_at")
            .having("SUM(seed_events.points) > 0")
            .order("seeds DESC, first_at ASC")
    end

    private

    def events
      scope = SeedEvent.public_board
      scope = scope.since(self.class.week_start) if period == "week"
      scope = scope.where(room_id: room&.id) if period == "room"
      scope
    end

    def eligible_users
      scope = User.active
      scope = scope.where.not(role: Seeds::STAFF_ROLES) if Seeds::LEADERBOARD_EXCLUDE_STAFF
      scope
    end
  end
end
