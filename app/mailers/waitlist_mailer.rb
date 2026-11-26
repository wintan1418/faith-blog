# frozen_string_literal: true

# Emails for the app waitlist (AppWaitlistEntry):
#   joined   - right after someone joins: "you're on the list" (or, if their app
#              is already out, the download link straight away).
#   launched - when the iPhone or Android app is out (WaitlistLaunchJob).
class WaitlistMailer < ApplicationMailer
  STORES = {
    "ios" => { env: "IOS_STORE_URL", name: "iPhone", store: "the App Store", button: "Download on the App Store" },
    "android" => { env: "ANDROID_STORE_URL", name: "Android", store: "Google Play", button: "Get it on Google Play" }
  }.freeze

  def joined
    setup(params.fetch(:entry))
    @live = live_stores_for(@entry)
    subject = @live.any? ? "You're on the list, and Brethreign is ready for you" : "You're on the Brethreign app waitlist"
    mail to: @entry.email, subject: subject
  end

  def launched
    setup(params.fetch(:entry))
    @platform = params.fetch(:platform).to_s
    @store = STORES.fetch(@platform)
    @store_url = self.class.store_url(@platform)
    mail to: @entry.email, subject: "Brethreign is now on #{@store[:store]}"
  end

  def self.store_url(platform)
    env = STORES.dig(platform.to_s, :env)
    env && ENV[env].presence
  end

  def self.live?(platform) = store_url(platform).present?

  private

  def setup(entry)
    @entry = entry
    @host = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "brethreign.com"
    @site_url = Rails.application.routes.url_helpers.root_url(host: @host)
    @leave_url = Rails.application.routes.url_helpers.leave_waitlist_url(token: entry.leave_token, host: @host)
    headers["List-Unsubscribe"] = "<#{@leave_url}>"
  end

  def live_stores_for(entry)
    platforms = entry.platform == "both" ? %w[ios android] : [ entry.platform ]
    platforms.filter_map { |p| [ p, STORES[p], self.class.store_url(p) ] if self.class.live?(p) }
  end
end
