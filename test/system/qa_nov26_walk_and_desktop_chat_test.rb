# frozen_string_literal: true

require "application_system_test_case"

# QA board, 26 Nov 2026. "Your walk" on the phone feed (Y4WN7EFD) at 390px in
# the Android app, and the chat message menu on a computer (ZCHlJfXh,
# s79j8vDe). Screenshots go to SHOT_DIR when it's set.
module QaNov26Shots
  def shot(name)
    dir = ENV["SHOT_DIR"]
    return if dir.blank?

    sleep 0.4 # let fades finish
    page.save_screenshot(File.join(dir, "#{name}.png"))
  end

  def go_dark
    page.execute_script("localStorage.setItem('fc-dark', '1')")
  end

  def go_light
    page.execute_script("localStorage.removeItem('fc-dark')") rescue nil
  end
end

class QaNov26PhoneWalkTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include QaNov26Shots

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; NativeShare; NativeDownloads; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :android_walk_390 } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 390, height: 844, pixelRatio: 2, touch: true })
  end

  setup do
    @member = create_member("walk_abbie", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                          tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @member.user_reading_plans.create!(plan_slug: "psalms-30", current_day: 2)
    login_as @member, scope: :user
  end

  teardown do
    go_light
    Warden.test_reset!
  end

  test "Your walk shows near the top of the phone feed, scrolls sideways, folds, and its stats lead somewhere" do
    visit feed_path
    assert_selector "body.hotwire-native"
    find("#your-walk", visible: true)
    assert page.evaluate_script("document.querySelector('#your-walk').open")
    assert_selector "#your-walk .eg-walkstat", minimum: 4, visible: true
    assert_no_selector "aside.eg-left", visible: true # the desktop rail stays hidden on phones

    # Below the Today and Daily Bible cards, and in the first screenful.
    tops = page.evaluate_script(<<~JS)
      ({ today: document.querySelector(".eg-today").getBoundingClientRect().bottom,
         bible: document.querySelector("#daily_bible_card").getBoundingClientRect().bottom,
         walk: document.querySelector("#your-walk").getBoundingClientRect().top,
         row: document.querySelector(".eg-walkstrip-row").scrollWidth > document.querySelector(".eg-walkstrip-row").clientWidth,
         pageScroll: document.documentElement.scrollWidth > document.documentElement.clientWidth })
    JS
    assert_operator tops["walk"], :>, tops["today"]
    assert_operator tops["walk"], :>=, tops["bible"]
    assert tops["row"], "the stat cards scroll sideways"
    refute tops["pageScroll"], "the page itself doesn't scroll sideways"
    shot("390-y4wn-walk-strip-light")

    # Fold it: a one-line peek remains, and it stays folded next time.
    find("#your-walk summary").click
    assert_no_selector "#your-walk .eg-walkstat", visible: true
    assert_selector "#your-walk .eg-walkstrip-peek", visible: true
    shot("390-y4wn-walk-folded-light")
    visit feed_path
    find("#your-walk")
    refute page.evaluate_script("document.querySelector('#your-walk').open")
    find("#your-walk summary").click
    assert_selector "#your-walk .eg-walkstat", visible: true

    # Dark.
    go_dark
    visit feed_path
    assert_selector "html.theme-dark"
    find("#your-walk", visible: true)
    shot("390-y4wn-walk-strip-dark")

    # Tapping the plan opens it; See all opens the whole walk.
    find("#your-walk a.eg-walkstat.is-plan").click
    assert_current_path reading_plan_path("psalms-30")
    visit feed_path
    row = find("#your-walk .eg-walkstrip-row")
    page.execute_script("arguments[0].scrollLeft = arguments[0].scrollWidth", row)
    find("#your-walk a.eg-walkstat.is-more").click
    assert_current_path walk_path
    assert_selector "section.eg-walk", text: "Prayed this week"
    shot("390-y4wn-walk-page-dark")
  end
end

class QaNov26DesktopTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include QaNov26Shots

  setup do
    release = Announcement.maximum(:id).to_i
    @ada = create_member("ada_desk26", welcomed_at: Time.current, seen_release_id: release)
    @ben = create_member("ben_desk26", welcomed_at: Time.current, seen_release_id: release,
                                       tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @chat = Conversation.find_or_create_between!(@ada, @ben)
    @photo = @chat.messages.new(sender: @ada, body: "")
    @photo.images.attach(io: StringIO.new(png), filename: "Altar.png", content_type: "image/png")
    @photo.save!
    @short = @chat.messages.create!(sender: @ada, body: "alright mama")
    login_as @ben, scope: :user
  end

  teardown do
    go_light
    Warden.test_reset!
  end

  test "desktop: hover a message, hover React, pick an emoji; the photo opens in the viewer with Save" do
    [ false, true ].each do |dark|
      dark ? go_dark : go_light
      visit conversation_path(@chat)
      assert_selector(dark ? "html.theme-dark" : "html:not(.theme-dark)")
      emoji = dark ? "😂" : "❤️"

      find("##{dom_id(@short)} .msg-body").hover
      react = find("##{dom_id(@short)} .msg-actions .msg-action--react", visible: true)
      assert_no_selector "##{dom_id(@short)} .msg-react-pill", visible: true
      react.hover
      pill = find("##{dom_id(@short)} .msg-react-pill", visible: true)
      assert_equal "true", react["aria-expanded"]
      shot("desktop-zchl-react-pill-#{dark ? 'dark' : 'light'}")
      pill.find(".msg-react-quick", text: emoji).click
      assert_selector "##{dom_id(@short)} .msg-reactions .msg-reaction.is-mine", text: emoji
      shot("desktop-zchl-reaction-shown-#{dark ? 'dark' : 'light'}")
    end
    assert_equal "😂", @short.likes.find_by(user: @ben).reaction_emoji

    # Media: no download button on the photo; click opens the viewer with Save.
    assert_no_selector "##{dom_id(@photo)} .msg-image-wrap a"
    find("##{dom_id(@photo)} img.msg-image").click
    assert_selector ".fc-lightbox .fc-lightbox-save[href*='/files/']", visible: true
    shot("desktop-s79j-viewer-save-dark")
    find(".fc-lightbox-close").click

    # And Download is in the hover menu.
    find("##{dom_id(@photo)} img.msg-image").hover
    assert_selector "##{dom_id(@photo)} .msg-actions a.msg-action--download[href*='/files/']", visible: true
  end

  test "desktop: the feed keeps Your walk in the left rail and hides the phone strip" do
    visit feed_path
    assert_selector "aside.eg-left section.eg-walk", text: "Your walk", visible: true
    assert_no_selector "#your-walk", visible: true
    shot("desktop-y4wn-feed-rail")
  end

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  def png
    require "zlib"
    width, height = 240, 180
    rows = Array.new(height) { "\x00" + ([ 120.chr, 140.chr, 200.chr ].join * width) }.join
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1a\n".b + chunk.("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate(rows)) + chunk.("IEND", "")
  end
end
