# frozen_string_literal: true

# "Have you read your Bible today?": the feed card, the bar on chapter pages
# and the little settings sheet (plan, reminder, streak on profile).
# Responses are Turbo Streams that redraw whichever of the card and the bar
# are on the page; plain HTML requests go back where they came from.
class DailyBibleController < ApplicationController
  before_action :authenticate_user!
  before_action :set_habit
  skip_after_action :track_page_view, raise: false

  # "I've read it" (card or chapter page), or a minute spent on a chapter.
  def read
    sync_zone
    chapter = chapter_param
    source = params[:source].to_s.presence_in(BibleReadingDay::SOURCES) || (chapter ? "chapter" : "card")
    return head(:unprocessable_entity) if source == "dwell" && chapter.nil?

    @result = @habit.record_read!(source: source, chapter: chapter)
    @chapter = chapter
    @offer_prayer = source == "card" # the feed card opens "Pray it" straight away
    respond_with_card(notice: "Marked as read. See you tomorrow.")
  end

  # "Amen" on the prayer after reading.
  def amen
    @habit.record_prayer!
    @chapter = chapter_param
    respond_with_card(notice: "Amen.")
  end

  # The settings sheet: plan, reminder, streak on profile.
  def update
    sync_zone
    attrs = {}
    attrs[:plan_slug] = params[:plan_slug] if DailyBible::Plan.find(params[:plan_slug])
    attrs[:reminder_enabled] = boolean(:reminder_enabled) if params.key?(:reminder_enabled)
    attrs[:reminder_time] = params[:reminder_time] if params[:reminder_time].present?
    attrs[:show_streak] = boolean(:show_streak) if params.key?(:show_streak)
    @habit.update!(attrs)
    @chapter = chapter_param
    respond_with_card(notice: "Daily Bible settings saved.")
  end

  # Fold the card down, open it again, or put it away for today.
  def card
    case params[:state]
    when "collapsed" then @habit.update!(card_collapsed_on: @habit.today)
    when "open" then @habit.update!(card_collapsed_on: nil)
    when "hidden" then @habit.update!(card_hidden_on: @habit.today)
    end
    respond_with_card
  end

  # The browser's time zone, so "today" and the 7:00 reminder are the member's own.
  def zone
    sync_zone
    head :no_content
  end

  private

  def set_habit
    @habit = BibleHabit.for(current_user)
  end

  def sync_zone
    name = params[:time_zone].to_s
    @habit.update!(time_zone: name) if name.present? && name != @habit.time_zone && BibleHabit.valid_zone?(name)
  end

  def chapter_param
    ref = Scripture::Reference.from_slug(params[:chapter].to_s) if params[:chapter].present?
    ref&.chapter_reference
  end

  def boolean(key) = ActiveModel::Type::Boolean.new.cast(params[key]) == true

  def respond_with_card(notice: nil)
    respond_to do |format|
      format.turbo_stream { render "daily_bible/update" }
      format.html { redirect_back fallback_location: feed_path, notice: notice }
    end
  end
end
