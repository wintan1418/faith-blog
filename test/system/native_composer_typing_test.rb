# frozen_string_literal: true

require "application_system_test_case"

# "I type and nothing shows" in the Android app: the breath composer is a
# full-screen sheet on phones with Cancel / Save draft / Breathe stuck to the
# bottom of the scrolling form. With the keyboard up, the browser scrolled the
# caret only to the bottom edge of the form, right behind that bar, so new
# lines were typed out of sight. This drives the composer the way the app
# does (phone-sized window with the keyboard's worth of height gone, the app's
# user agent) and checks the caret stays above the bar.
class NativeComposerTypingTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  # 412 wide like a Pixel; 470 tall is what's left above the keyboard.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 470 ] do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 470, pixelRatio: 2.625, touch: true })
  end

  setup do
    @member = create_member("typing_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "what you type in the breath composer stays above the Cancel / Breathe bar" do
    visit feed_path
    assert_selector "body.hotwire-native"

    page.execute_script(%(document.querySelector("[data-action~='click->composer-modal#open']").click()))
    editor = find("dialog.fc-composer-dialog trix-editor", visible: true)
    assert page.evaluate_async_script(<<~JS), "editor never loaded"
      const done = arguments[arguments.length - 1]
      const editor = document.querySelector("dialog.fc-composer-dialog trix-editor")
      const wait = () => editor.editor ? done(true) : setTimeout(wait, 50)
      wait()
    JS

    editor.click
    12.times do |i|
      editor.send_keys("Line #{i + 1}")
      editor.send_keys(:enter) unless i == 11
    end

    gap = nil
    10.times do
      gap = page.evaluate_script(<<~JS)
        (() => {
          const editor = document.querySelector("dialog.fc-composer-dialog trix-editor")
          const [ position ] = editor.editor.getSelectedRange()
          const caret = editor.editor.getClientRectAtPosition(position)
          const bar = document.querySelector("dialog.fc-composer-dialog .fc-composer-footer")
          return bar.getBoundingClientRect().top - caret.bottom
        })()
      JS
      break if gap >= 0
      sleep 0.1
    end

    assert_operator gap, :>=, 0, "the caret is #{-gap.to_i}px behind the Cancel / Breathe bar"
  end

  test "boxes you type into are never unselectable in the app, even inside a label" do
    visit feed_path
    assert_selector "body.hotwire-native"

    blocked = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]), textarea, select, trix-editor")]
        .filter((field) => getComputedStyle(field).userSelect === "none")
        .map((field) => field.outerHTML.slice(0, 80))
    JS
    assert_empty blocked

    # The Room pill wraps its picker in a <label>, which the app makes unselectable.
    room = page.evaluate_script(%(getComputedStyle(document.querySelector("label.fc-composer-pill select")).userSelect))
    assert_equal "text", room
  end
end
