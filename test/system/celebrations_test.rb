# frozen_string_literal: true

require "application_system_test_case"

# Brethreign Celebrates in the browser: the pop-up opens once, the banner
# closes and stays closed, the share card draws, and the strip on other pages.
module CelebrationSystemSteps
  extend ActiveSupport::Concern

  included do
    include Warden::Test::Helpers

    setup do
      Announcement.releases.delete_all
      @member = create_member("cel_sys_#{SecureRandom.hex(2)}", welcomed_at: Time.current, tour_completed_at: Time.current,
                                                              onboarding_dismissed_at: Time.current)
      @occasion = Celebration.create!(name: "Thanksgiving", greeting_title: "Happy Thanksgiving", emblem: "🍂", effect: "leaves",
                                      accent_color: "#b45309", message: "Grateful for every one of you.", hashtag: "Thanksgiving",
                                      scripture_reference: "Psalm 100:4",
                                      scripture_text: "Enter into his gates with thanksgiving, and into his courts with praise.",
                                      starts_at: 1.hour.ago, ends_at: 1.day.from_now, status: :live)
      login_as @member, scope: :user
    end

    teardown { Warden.test_reset! }
  end

  def check_popup_banner_and_card
    visit feed_path
    assert_selector "dialog#celebration-popup[open]", wait: 5
    find("dialog#celebration-popup .cel-close").click
    assert_no_selector "dialog#celebration-popup[open]", wait: 3
    assert wait_until { @member.reload.card_dismissed?(@occasion.popup_key) }, "pop-up wasn't remembered"

    # Share card: the sheet opens and draws the card.
    within("#celebration-banner") { find("[data-testid=celebration-share-card]").click }
    assert_selector "dialog.cel-card-sheet canvas[data-testid=celebration-card-canvas]", wait: 10
    size = page.evaluate_script(%(document.querySelector("dialog.cel-card-sheet canvas").width + "x" + document.querySelector("dialog.cel-card-sheet canvas").height))
    assert_includes %w[1080x1920 1080x1080], size
    find("dialog.cel-card-sheet [data-format=square]").click
    assert_equal "1080x1080", page.evaluate_script(%(document.querySelector("dialog.cel-card-sheet canvas").width + "x" + document.querySelector("dialog.cel-card-sheet canvas").height))
    find("dialog.cel-card-sheet .share-sheet-close").click
    assert_no_selector "dialog.cel-card-sheet", wait: 3

    # The pop-up doesn't come back.
    visit feed_path
    assert_selector "#celebration-banner"
    assert_no_selector "#celebration-popup", visible: :all

    # Dismiss the banner: gone now and after reloading.
    within("#celebration-banner") { find(".cel-close").click }
    assert_no_selector "#celebration-banner", wait: 3
    assert wait_until { @member.reload.card_dismissed?(@occasion.dismissal_key) }, "dismissal wasn't remembered"
    visit feed_path
    assert_no_selector "#celebration-banner"
  end

  def wait_until(seconds = 4)
    deadline = Time.current + seconds
    loop do
      return true if yield
      return false if Time.current > deadline

      sleep 0.1
    end
  end
end

class CelebrationsDesktopTest < ApplicationSystemTestCase
  include CelebrationSystemSteps

  test "desktop: pop-up once, share card, dismiss" do
    check_popup_banner_and_card
  end

  test "Share a greeting opens the composer with the greeting" do
    @member.dismiss_card!(@occasion.popup_key)
    visit feed_path
    within("#celebration-banner") { click_on "Share a greeting" }
    assert_selector "dialog.fc-composer-dialog[open] trix-editor", wait: 5
    assert page.has_text?("Happy Thanksgiving, brethren!", wait: 5)
    assert_includes find("dialog.fc-composer-dialog trix-editor").text, "#Thanksgiving"
  end

  test "the strip shows on other main pages and closes" do
    @member.dismiss_card!(@occasion.popup_key)
    visit leaderboard_path
    assert_selector "#celebration-strip", text: "Happy Thanksgiving"
    within("#celebration-strip") { find(".cel-close").click }
    assert_no_selector "#celebration-strip", wait: 3
  end
end

class CelebrationsPhoneTest < ApplicationSystemTestCase
  include CelebrationSystemSteps

  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :celebrations_phone } do |options|
    options.add_emulation(device_metrics: { width: 390, height: 844, pixelRatio: 3, touch: true })
  end

  test "390px: pop-up once, share card, dismiss" do
    check_popup_banner_and_card
  end

  test "390px: the banner fits without sideways scrolling" do
    @member.dismiss_card!(@occasion.popup_key)
    visit feed_path
    assert_selector "#celebration-banner"
    assert_equal 0, page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    right = page.evaluate_script(%(Math.round(document.querySelector("#celebration-banner").getBoundingClientRect().right)))
    assert_operator right, :<=, 390
  end
end

class CelebrationsNativeTest < ApplicationSystemTestCase
  include CelebrationSystemSteps

  APP_USER_AGENT = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ], options: { name: :celebrations_native } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 900, pixelRatio: 2.625, touch: true })
  end

  test "in the app: banner and pop-up work in body.hotwire-native" do
    visit feed_path
    assert_selector "body.hotwire-native"
    check_popup_banner_and_card
  end
end
