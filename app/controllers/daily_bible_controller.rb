# frozen_string_literal: true

# "Have you read your Bible today?": the feed card, the bar on chapter pages
# and the little settings sheet (plan, reminder, streak on profile).
# Responses are Turbo Streams that redraw whichever of the card and the bar
# are on the page; plain HTML requests go back where they came from.
class DailyBibleController < ApplicationController
  before_action :authenticate_user!, except: :start
  before_action :set_habit, except: :start
  member_rate_limit to: 12, within: 1.hour, only: :share, name: "bible-share",
                    message: "That's a lot of sharing for one hour. Try again a little later."
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

  # The "Share what I read" form, loaded into its sheet when it opens.
  def new_share
    @chapter = chapter_param
    return head(:not_found) unless @chapter

    @prayer = ChapterPrayer.for(@chapter)
    @passage = Scripture::Passage.new(@chapter)
    @note = ChapterNote.for(current_user, @chapter)
    render partial: "daily_bible/share_form", locals: { chapter: @chapter, prayer: @prayer, passage: @passage, note: @note, habit: @habit }
  end

  # "Share what I read": posts the chapter as a reading card on the feed
  # (ReadingShare), with what stood out (the post's words), a key verse,
  # today's prayer burden and the member's notes when they ticked them.
  def share
    chapter = chapter_param
    return head(:unprocessable_entity) unless chapter

    note = params[:note].to_s.gsub(/\r\n?/, "\n").strip.first(ReadingShare::NOTE_MAX)
    share = ReadingShare.build(user: current_user, chapter: chapter, verse_slug: params[:verse],
                               include_burden: boolean(:include_burden), include_notes: boolean(:include_notes),
                               has_note: note.present?)
    body = note.present? ? note.split(/\n{2,}/).map { |para| "<div>#{ERB::Util.html_escape(para).gsub("\n", "<br>")}</div>" }.join : "I read #{chapter} today."
    post = current_user.posts.build(content: body, reading_share: share, status: :published, moderation_status: :approved)
    if post.save
      redirect_to post_path(post), status: :see_other, notice: "Shared. Your reading card invites others to read #{chapter} too."
    else
      redirect_back fallback_location: scripture_page_path(chapter.slug), alert: post.errors.full_messages.to_sentence.presence || "Couldn't share that."
    end
  end

  # "My notes" on a chapter page: private, saved per chapter.
  def notes
    @chapter = chapter_param
    return head(:unprocessable_entity) unless @chapter

    @note = ChapterNote.write!(current_user, @chapter, params[:body])
    @notes_saved = true
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("chapter_notes", partial: "daily_bible/notes", locals: { chapter: @chapter, note: @note, saved: true }) }
      format.html { redirect_to scripture_page_path(@chapter.slug, anchor: "chapter_notes"), notice: @note ? "Notes saved." : "Notes cleared." }
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to scripture_page_path(@chapter.slug, anchor: "chapter_notes"), alert: e.record.errors.full_messages.to_sentence
  end

  # "Start your daily reading" from someone's shared reading card: the feed
  # card with its plan picker open; guests sign up first and come back here.
  def start
    unless user_signed_in?
      store_location_for(:user, daily_bible_start_path)
      return redirect_to new_user_registration_path
    end

    habit = BibleHabit.for(current_user)
    habit.update!(card_hidden_on: nil, card_collapsed_on: nil) if habit.card_hidden_today? || habit.card_collapsed_today?
    redirect_to feed_path(bible: "plans", anchor: "daily_bible_card")
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
