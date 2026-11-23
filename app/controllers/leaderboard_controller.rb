# frozen_string_literal: true

# Seeds leaderboard: this week, all time, or one room. The viewer always sees
# their own line, even when they're not in the top list.
class LeaderboardController < ApplicationController
  before_action :authenticate_user!

  TOP = 20

  def index
    @tab = Seeds::Leaderboard::PERIODS.include?(params[:tab]) ? params[:tab] : "week"
    if @tab == "room"
      @rooms = Room.public_rooms.ordered
      @room = @rooms.find_by(slug: params[:room]) || @rooms.first
    end
    board = Seeds::Leaderboard.new(period: @tab, room: @room)
    @rows = board.top(TOP)
    @founders = board.founders
    @mine = board.position_of(current_user)
  end
end
