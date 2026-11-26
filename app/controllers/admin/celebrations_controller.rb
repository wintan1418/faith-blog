# frozen_string_literal: true

# Admin → Celebrations: special occasions members see as a banner, a strip,
# a one-time pop-up and a share card while they run.
class Admin::CelebrationsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_celebration, only: %i[edit update destroy activate deactivate]
  layout "admin"

  def index
    now = Time.current
    all = Celebration.includes(:post, artwork_attachment: :blob).order(:starts_at).to_a
    @running = all.select { |c| c.running?(now) }
    @upcoming = all.select { |c| c.starts_at > now }
    @past = all.select { |c| c.ends_at <= now }.reverse.first(20)
    @auto_activate = Celebration.auto_activate_presets?
  end

  def new
    zone = "Africa/Lagos"
    today = Time.current.in_time_zone(zone).beginning_of_day
    @celebration = Celebration.new(time_zone: zone, starts_at: today, ends_at: today + 1.day, share_card: true)
  end

  def create
    @celebration = Celebration.new(celebration_params)
    @celebration.status = :live if params[:activate].present?
    if @celebration.save
      redirect_to admin_celebrations_path, notice: "#{@celebration.name} saved#{' and live' if @celebration.live?}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @celebration.artwork.purge_later if params.dig(:celebration, :remove_artwork) == "1"
    if @celebration.update(celebration_params)
      redirect_to admin_celebrations_path, notice: "#{@celebration.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @celebration.destroy
    redirect_to admin_celebrations_path, notice: "Occasion deleted."
  end

  def activate
    if @celebration.update(status: :live)
      redirect_to admin_celebrations_path, notice: "#{@celebration.name} is live#{@celebration.running? ? ' now' : " from #{@celebration.local_starts_at.strftime('%-d %b, %H:%M')}"}."
    else
      redirect_to edit_admin_celebration_path(@celebration), alert: @celebration.errors.full_messages.to_sentence
    end
  end

  def deactivate
    @celebration.update_column(:status, Celebration.statuses[:draft])
    redirect_to admin_celebrations_path, notice: "#{@celebration.name} is back to draft."
  end

  def seed_presets
    created = Celebrations::Presets.seed!
    redirect_to admin_celebrations_path,
                notice: created.any? ? "Added #{created.size} occasion(s) for the next 12 months#{Celebration.auto_activate_presets? ? '' : ' as drafts'}." : "The calendar is already up to date."
  end

  def auto_activate
    SiteSetting.switch(Celebration::AUTO_ACTIVATE_SETTING, params[:on] == "1")
    redirect_to admin_celebrations_path, notice: "Auto-activate presets is #{Celebration.auto_activate_presets? ? 'on' : 'off'}."
  end

  private

  def set_celebration
    @celebration = Celebration.find(params[:id])
  end

  def celebration_params
    params.expect(celebration: [ :name, :greeting_title, :message, :scripture_reference, :scripture_text, :hashtag,
                                 :accent_color, :emblem, :effect, :starts_local, :ends_local, :time_zone, :audience,
                                 :country_list, :post_link, :share_card, :artwork, { country_codes: [] } ])
  end
end
