# frozen_string_literal: true

require "application_system_test_case"

# On phones the emoji picker is a sheet pinned to the bottom of the screen
# (position: fixed). Breath cards lifted with a transform on :hover, and on
# Android a tap leaves :hover stuck on the card. A transformed ancestor traps
# fixed children, so the "sheet" sat at the bottom of the card, right over the
# reply box, and you couldn't see the emoji you picked. These tests open the
# picker in a feed thread with the card transformed (as a stuck hover leaves
# it) and check the sheet is on the screen's bottom with the reply box above it.
class EmojiSheetAndroidTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 820 ] do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 820, pixelRatio: 2.625, touch: true })
  end

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("emoji_sheet_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                                  tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    author = create_member("emoji_sheet_author")
    room = Room.create!(name: "Emoji Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Rejoice always", content: "Grace and peace " * 40,
                         status: :published, moderation_status: :approved, allow_comments: true)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "the emoji sheet in a feed thread sits at the bottom of the screen, below the reply box" do
    visit feed_path
    assert_selector "body.hotwire-native"
    find("##{ActionView::RecordIdentifier.dom_id(@post)} [data-controller='thread-toggle']").click
    textarea = find("##{ActionView::RecordIdentifier.dom_id(@post, :inline_form)} textarea", visible: true)

    # What a stuck :hover did to the card before the fix.
    page.execute_script(%(document.querySelector("#{'#' + ActionView::RecordIdentifier.dom_id(@post)}").style.transform = "translateY(-1px)"))
    find("##{ActionView::RecordIdentifier.dom_id(@post, :inline_form)} [data-emoji-picker-target='button']").click
    sleep 1 # sheet animation + the smooth scroll that lifts the reply box

    layout = page.evaluate_script(<<~JS)
      (() => {
        const form = document.getElementById("#{ActionView::RecordIdentifier.dom_id(@post, :inline_form)}")
        const sheet = form.querySelector("[data-emoji-picker-target='picker']").getBoundingClientRect()
        const box = form.querySelector("textarea").getBoundingClientRect()
        return { sheetTop: sheet.top, sheetBottom: sheet.bottom, boxBottom: box.bottom, viewport: window.innerHeight }
      })()
    JS

    assert_operator layout["sheetBottom"], :<=, layout["viewport"], "sheet runs off the bottom of the screen: #{layout}"
    assert_operator layout["sheetBottom"], :>=, layout["viewport"] - 40, "sheet isn't at the bottom of the screen: #{layout}"
    assert_operator layout["boxBottom"], :<=, layout["sheetTop"], "sheet covers the reply box: #{layout}"

    # Several emoji in a row land in the box and the sheet stays open.
    %w[🙏 ❤️ 😊].each do |emoji|
      page.execute_script(<<~JS)
        document.querySelector("##{ActionView::RecordIdentifier.dom_id(@post, :inline_form)} emoji-picker")
          .dispatchEvent(new CustomEvent("emoji-click", { detail: { unicode: "#{emoji}" }, bubbles: true }))
      JS
    end
    assert_equal "🙏 ❤️ 😊", textarea.value.strip
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@post, :inline_form)} [data-emoji-picker-target='picker']", visible: true
  end
end
