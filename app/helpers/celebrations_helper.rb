# frozen_string_literal: true

# Brethreign Celebrates on member pages: which occasion this member sees,
# where its strip goes, and the data its share card is drawn from.
module CelebrationsHelper
  # Main pages that get the lighter strip (the feed has the full banner;
  # chats, settings and forms stay quiet).
  STRIP_CONTROLLERS = %w[
    around answered_prayers bookmarks circles games leaderboard notifications
    pages rooms search series users church_history blog
  ].freeze

  # The live occasion for the signed-in member that they haven't closed, or nil.
  # Never breaks a page: on any error there is simply no celebration.
  def current_celebration
    return @current_celebration if defined?(@current_celebration)

    @current_celebration = begin
      if user_signed_in?
        Celebration.current_for(current_user, country: celebration_country)
      end
    rescue StandardError => e
      Rails.logger.warn("[celebrations] #{e.class}: #{e.message}")
      nil
    end
  end

  # The member's country: their city when they've set one, else where the
  # request comes from (Cloudflare), else unknown.
  def celebration_country
    current_user&.profile&.city&.country_code.presence ||
      request.headers["CF-IPCountry"].to_s.upcase[/\A[A-Z]{2}\z/].then { |c| c unless %w[XX T1].include?(c) }
  end

  def celebration_strip_page?
    STRIP_CONTROLLERS.include?(controller_path) && action_name.in?(%w[index show])
  end

  # The gentle one-time pop-up: not while "What's new" is showing, not on
  # chats or forms, and only once per occasion.
  def celebration_popup?(celebration, release_showing:)
    return false if celebration.nil? || release_showing || hotwire_native_modal?
    return false unless controller_path == "feed" || celebration_strip_page?

    !current_user.card_dismissed?(celebration.popup_key)
  end

  def celebration_style(celebration)
    "--cel-accent: #{celebration.accent_color};"
  end

  def celebration_art_url(celebration)
    celebration.artwork.attached? ? photo_src(celebration.artwork, width: 1200) : nil
  rescue StandardError
    nil
  end

  # What the share card (share/celebration_card.js) draws.
  def celebration_card_data(celebration)
    {
      id: celebration.id,
      title: celebration.greeting_title,
      message: celebration.message,
      verse: celebration.scripture_text,
      reference: celebration.scripture_reference,
      accent: celebration.accent_color,
      emblem: celebration.emblem,
      effect: celebration.effect,
      username: current_user&.username,
      link: root_url,
      art: celebration.artwork.attached? ? { url: nil, fallback: rails_storage_proxy_path(celebration.artwork) } : nil,
      share_text: celebration.friend_message(root_url)
    }.to_json
  rescue StandardError
    {}.to_json
  end

  private

  # A native modal screen (a form presented by the app) never gets the pop-up.
  def hotwire_native_modal?
    hotwire_native_app? && request.path.end_with?("/new", "/edit")
  end
end
