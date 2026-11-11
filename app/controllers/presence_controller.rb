# frozen_string_literal: true

# Who's online. The signed-in layout pings #ping every ~45s while the page is
# visible (presence_controller.js), and the feed reloads #strip every ~30s.
class PresenceController < ApplicationController
  # The ping runs constantly for every open tab, so it does only one cheap write.
  skip_before_action :touch_last_seen, :require_supported_app_version
  skip_after_action :track_page_view

  before_action :authenticate_user!, only: :strip

  # Two tabs (or a page load right before a beat) shouldn't write twice.
  PING_THROTTLE = 15.seconds

  def ping
    return head(:unauthorized) unless user_signed_in?

    last = current_user.last_seen_at
    current_user.update_column(:last_seen_at, Time.current) if last.nil? || last < PING_THROTTLE.ago
    head :no_content
  end

  # The feed's "Online now" row, as a Turbo Frame.
  def strip
    render partial: "presence/strip", locals: { online: OnlinePresence.new(current_user) }
  end
end
