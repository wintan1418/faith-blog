# frozen_string_literal: true

# Fresh badge numbers for a page coming back into view (a phone unlocked, the
# app reopened, a tab switched back), when it may have missed live updates.
class UnreadCountsController < ApplicationController
  before_action :authenticate_user!

  def show
    response.headers["Cache-Control"] = "no-store"
    render json: { messages: current_user.unread_conversations_count, notifications: current_user.unread_notifications_count }
  end
end
