# frozen_string_literal: true

# The Updates bots: each source's health, what was posted, and switches.
class Admin::BotsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!
  layout "admin"

  def index
    @sources = BotSource.order(:bot, :topic, :name)
    @live_counts = BotItem.live.group(:bot_source_id).count
    @today = BotItem.where(status: %i[live hidden]).where(created_at: Time.current.beginning_of_day..).group(:bot).count
    @bot_filter = Bots::Catalog.find(params[:bot])&.key
    items = BotItem.where(status: %i[live hidden]).includes(:bot_source).newest
    items = items.where(bot: @bot_filter) if @bot_filter
    @items = items.limit(60)
  end

  def refresh
    BotsRefreshJob.perform_later(params[:bot].presence_in(Bots::Catalog.keys), force: true)
    redirect_to admin_bots_path, notice: "Fetching now. New updates appear in a minute or two."
  end

  def toggle_source
    source = BotSource.find(params[:id])
    source.update!(active: !source.active)
    redirect_to admin_bots_path, notice: "#{source.name} #{source.active ? 'switched on' : 'switched off'}."
  end

  def toggle_item
    item = BotItem.where(status: %i[live hidden]).find(params[:id])
    item.update!(status: item.live? ? :hidden : :live)
    redirect_back fallback_location: admin_bots_path, notice: item.hidden? ? "Hidden from Updates." : "Shown in Updates again."
  end
end
