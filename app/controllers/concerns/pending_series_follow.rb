# frozen_string_literal: true

# A signed-out visitor tapped "Follow series": the series waits in their
# session, and the first page they open once signed in (sign-up or sign-in,
# web or app) completes the follow.
module PendingSeriesFollow
  extend ActiveSupport::Concern

  KEY = :pending_series_follow

  included do
    before_action :complete_pending_series_follow, if: -> { session[KEY].present? && user_signed_in? }
  end

  def self.remember(session, series)
    session[KEY] = series.id
  end

  private

  def complete_pending_series_follow
    series = Series.find_by(id: session.delete(KEY))
    return unless series && !series.author?(current_user) && series.readable_by?(current_user)

    current_user.series_follows.find_or_create_by!(series: series)
    flash.now[:notice] = "You're following “#{series.title}”. You'll hear when a new part is up."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end
end
