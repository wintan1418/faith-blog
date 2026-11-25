# frozen_string_literal: true

class WelcomeMailer < ApplicationMailer
  def welcome
    @user = params.fetch(:user)
    @existing = params.fetch(:existing, false)
    @host = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
    @feed_url = Rails.application.routes.url_helpers.feed_url(host: @host)
    token = Rails.application.message_verifier(:weekly_digest_unsubscribe).generate(@user.id, expires_in: 90.days)
    @unsubscribe_url = Rails.application.routes.url_helpers.email_unsubscribes_weekly_digest_url(token: token, host: @host)
    @step_urls = step_urls
    @ios_url = ENV["IOS_STORE_URL"].presence
    @android_url = ENV["ANDROID_STORE_URL"].presence

    mail to: @user.email, subject: WelcomeNote.subject(@user)
  end

  private

  def step_urls
    routes = Rails.application.routes.url_helpers
    { profile: routes.edit_settings_profile_url(host: @host), bible: todays_chapter_url(routes),
      rooms: routes.rooms_url(host: @host) }
  end

  # The first chapter of their reading plan (the default plan for someone
  # new), or the feed's Bible card if that can't be worked out.
  def todays_chapter_url(routes)
    chapter = (@user.bible_habit || BibleHabit.new(user: @user)).portion&.first
    chapter ? routes.scripture_page_url(chapter.slug, host: @host) : routes.feed_url(host: @host)
  rescue StandardError
    routes.feed_url(host: @host)
  end
end
