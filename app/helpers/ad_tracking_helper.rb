# frozen_string_literal: true

# Meta Pixel and Google tag, for measuring ads. Off until META_PIXEL_ID and/or
# GOOGLE_TAG_ID are set; never inside the apps. Visitors from Europe and the UK
# must say yes first (GDPR); elsewhere tags load unless someone says no.
module AdTrackingHelper
  CONSENT_COUNTRIES = %w[
    AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
    IS LI NO GB CH
  ].freeze

  def meta_pixel_id = ENV["META_PIXEL_ID"].to_s.strip.presence&.then { |id| id if id.match?(/\A\d{6,20}\z/) }
  def google_tag_id = ENV["GOOGLE_TAG_ID"].to_s.strip.presence&.then { |id| id if id.match?(/\A(G|AW)-[A-Z0-9]{4,20}\z/) }
  # Google Ads sign-up conversion, e.g. "AW-123456789/AbC-dEfGh"
  def google_ads_signup = ENV["GOOGLE_ADS_SIGNUP_CONVERSION"].to_s.strip.presence&.then { |id| id if id.match?(%r{\AAW-\d+/[\w-]+\z}) }

  def ad_tracking_enabled?
    !hotwire_native_app? && (meta_pixel_id.present? || google_tag_id.present?)
  end

  # Unknown country (no Cloudflare header) counts as "ask first", to be safe.
  def ad_consent_required?
    country = request.headers["CF-IPCountry"].to_s.upcase
    country.blank? || country == "XX" || CONSENT_COUNTRIES.include?(country)
  end
end
