# frozen_string_literal: true

class WeeklyDigestMailer < ApplicationMailer
  WINDOW = 7.days

  # Sends a Sunday-morning digest to one user. Skipped when the user has
  # turned off email notifications (the job already filters, this is the
  # belt-and-braces guard for direct invocation).
  def weekly_digest
    @user = params.fetch(:user)
    return if @user.email_notifications_enabled == false

    @range = WINDOW.ago.beginning_of_day..Time.current
    @host  = default_url_host
    @top_breaths    = top_breaths_for(@user)
    @user_breaths   = @user.posts.where(status: :published, published_at: @range).count
    @open_prayers   = open_prayers_for(@user)
    @streak         = @user.current_breath_streak.to_i
    @longest_streak = @user.longest_breath_streak.to_i
    @unsubscribe_url = build_unsubscribe_url(@user)
    @feed_url        = Rails.application.routes.url_helpers.feed_url(host: default_url_host)

    mail to: @user.email,
         subject: weekly_subject(@top_breaths.size, @user_breaths)
  end

  private

  def top_breaths_for(user)
    following_ids = user.following.pluck(:id)

    # Followers have a circle to draw from; brand new accounts get the
    # featured / community-wide best so the email isn't empty.
    base =
      if following_ids.any?
        Post.where(user_id: following_ids)
      else
        Post.where(featured: true)
      end

    base.where(status: :published, published_at: @range)
        .where(anonymous: [ false, nil ])
        .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
        .limit(5)
        .includes(:user, :room)
  end

  def open_prayers_for(user)
    user.prayed_for_posts
        .where(prayer_status: Post.prayer_statuses[:prayer_pending])
        .order(updated_at: :desc)
        .limit(3)
        .includes(:user)
  end

  def weekly_subject(breaths_seen, user_breaths)
    if user_breaths.zero? && breaths_seen.zero?
      "Brethreign — your circle is quiet, come back in"
    elsif user_breaths.zero?
      "Your week at Brethreign — #{breaths_seen} breaths from your circle"
    else
      "Your week at Brethreign — you breathed #{user_breaths} time#{user_breaths == 1 ? "" : "s"}"
    end
  end

  def build_unsubscribe_url(user)
    token = Rails.application.message_verifier(:weekly_digest_unsubscribe).generate(user.id, expires_in: 30.days)
    Rails.application.routes.url_helpers.email_unsubscribes_weekly_digest_url(token: token, host: default_url_host)
  end

  def default_url_host
    Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
  end
end
