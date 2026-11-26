# frozen_string_literal: true

require "application_system_test_case"

# QA board, 26 Nov 2026 (Abbie, Android app), checked at iPhone width (390px)
# with the Android app's user agent and touch:
#   ZCHlJfXh  the ⋯ menu beside a message lost its reactions. The menu was
#             anchored to the bubble's right edge and, beside a short incoming
#             message, ran off the left of the screen, taking React with it.
#   s79j8vDe  no loud download buttons on photos and voice notes: tap a photo
#             to view it (Save in the viewer), tap a voice note to play it,
#             Download in the ⋯ menu.
# Screenshots go to SHOT_DIR when it's set.
class ChatMediaDownloadsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; NativeShare; NativeDownloads; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  # Its own driver name: system test classes that share ":selenium" share one
  # browser, so another class's user agent and screen size would leak in.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :android_chat_menu_390 } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_argument("--autoplay-policy=no-user-gesture-required")
    options.add_emulation(device_metrics: { width: 390, height: 844, pixelRatio: 2, touch: true })
  end

  setup do
    release = Announcement.maximum(:id).to_i
    @ada = create_member("ada_media", welcomed_at: Time.current, seen_release_id: release)
    @ben = create_member("ben_media", welcomed_at: Time.current, seen_release_id: release)
    @chat = Conversation.find_or_create_between!(@ada, @ben)

    @photos = @chat.messages.new(sender: @ada, body: "")
    2.times { |i| @photos.images.attach(io: StringIO.new(png(80 + (i * 90))), filename: "Sunday #{i + 1}.png", content_type: "image/png") }
    @photos.save!
    @photo = @chat.messages.new(sender: @ada, body: "")
    @photo.images.attach(io: StringIO.new(png(200)), filename: "Altar.png", content_type: "image/png")
    @photo.save!
    @voice = @chat.messages.new(sender: @ada, body: "")
    @voice.voice_note.attach(io: StringIO.new(wav), filename: "voice-note.wav", content_type: "audio/wav")
    @voice.save!(validate: false)
    @mine = @chat.messages.create!(sender: @ben, body: "Thank you so much my brother")
    # Short and incoming: the case where the menu used to run off the left edge.
    @short = @chat.messages.create!(sender: @ada, body: "alright mama")

    login_as @ben, scope: :user
  end

  teardown { Warden.test_reset! }

  test "phone: tap a short incoming message, react from the menu, the reaction shows under it" do
    visit conversation_path(@chat)
    assert_selector "body.hotwire-native"

    bubble = find("##{dom_id(@short)} .msg-bubble")
    bubble.find(".msg-body").click
    menu = find("##{dom_id(@short)} .msg-actions.is-open")
    assert_menu_on_screen(menu)
    assert_no_selector "##{dom_id(@short)} .msg-react-quick", visible: true # not spread out in the menu
    shot("zchl-menu-open-light")

    pill = open_pill(@short)
    assert_selector "##{dom_id(@short)} .msg-react-quick", count: 6, visible: true
    shot("zchl-react-pill-light")
    pill.find(".msg-react-quick", text: "🙏").click
    assert_selector "##{dom_id(@short)} .msg-reactions .msg-reaction.is-mine", text: "🙏"
    assert_no_selector ".msg-actions.is-open"
    assert_equal "🙏", @short.likes.find_by(user: @ben)&.reaction_emoji
    shot("zchl-reaction-shown-light")

    # Tapping your reaction in the menu again takes it back.
    find("##{dom_id(@short)} .msg-body").click
    open_pill(@short).find(".msg-react-quick.is-mine", text: "🙏").click
    assert_no_selector "##{dom_id(@short)} .msg-reactions"
    assert_nil @short.likes.find_by(user: @ben)
  end

  test "phone: a long press opens the menu, the + opens every emoji" do
    visit conversation_path(@chat)
    long_press("##{dom_id(@mine)} .msg-body")
    menu = find("##{dom_id(@mine)} .msg-actions.is-open")
    assert_menu_on_screen(menu)

    # Escape closes the pill, the menu stays.
    open_pill(@mine)
    page.send_keys(:escape)
    assert_no_selector "##{dom_id(@mine)} .msg-react-pill", visible: true
    assert_selector "##{dom_id(@mine)} .msg-actions.is-open"

    open_pill(@mine).find(".msg-react-more").click
    assert_selector "##{dom_id(@mine)} .fc-reaction-picker:not(.hidden) emoji-picker", visible: true
    # Choosing from the full picker reacts too.
    page.execute_script(<<~JS)
      document.querySelector("##{dom_id(@mine)} emoji-picker")
        .dispatchEvent(new CustomEvent("emoji-click", { detail: { unicode: "🔥" } }))
    JS
    assert_selector "##{dom_id(@mine)} .msg-reactions .msg-reaction", text: "🔥"
  end

  test "phone: tap a photo to view it with Save, ⋯ has Download; no buttons on the bubble" do
    visit conversation_path(@chat)
    assert_no_selector ".msg-bubble .msg-media-get"
    assert_no_selector ".msg-image-wrap a"
    shot("s79j-media-quiet-light")

    find("##{dom_id(@photo)} img.msg-image").click
    assert_selector ".fc-lightbox .fc-lightbox-img", visible: true
    save = find(".fc-lightbox .fc-lightbox-save", visible: true)
    assert_match %r{/inbox/\d+/messages/#{@photo.id}/files/\d+/Altar\.png\z}, save[:href]
    shot("s79j-viewer-save")
    find(".fc-lightbox-close").click
    assert_no_selector ".fc-lightbox"

    # One photo: ⋯ → Download links to the file itself (the app saves it).
    find("##{dom_id(@photo)} .msg-more").click
    menu = find("##{dom_id(@photo)} .msg-actions.is-open")
    assert_menu_on_screen(menu)
    download = menu.find("a.msg-action--download", visible: true)
    assert_match %r{/files/\d+/Altar\.png\z}, download[:href]
    shot("s79j-photo-menu-download")
    page.execute_script("document.addEventListener('click', e => { if (e.target.closest('.msg-action--download')) e.preventDefault() }, { once: true })")
    download.click
    assert_no_selector ".msg-actions.is-open"

    # Several photos: ⋯ → Save opens the viewer.
    find("##{dom_id(@photos)} .msg-more").click
    find("##{dom_id(@photos)} .msg-actions.is-open button.msg-action--download").click
    assert_selector ".fc-lightbox .fc-lightbox-counter", text: "1 / 2"
    find(".fc-lightbox-close").click
  end

  test "phone: tapping a voice note plays it; Download is in its menu" do
    visit conversation_path(@chat)
    player = find("##{dom_id(@voice)} .msg-voice-player")
    assert_no_selector "##{dom_id(@voice)} .msg-voice-row a"

    player.find(".msg-voice-play").click
    assert_selector "##{dom_id(@voice)} .msg-voice-player.is-playing"
    assert page.evaluate_script("!document.querySelector('##{dom_id(@voice)} audio').paused"), "the voice note plays"
    shot("s79j-voice-playing")
    player.find(".msg-voice-play").click
    assert_no_selector "##{dom_id(@voice)} .msg-voice-player.is-playing"

    # Tapping the waveform plays it too.
    player.find(".msg-wave").click
    assert_selector "##{dom_id(@voice)} .msg-voice-player.is-playing"
    player.find(".msg-voice-play").click

    find("##{dom_id(@voice)} .msg-more").click
    download = find("##{dom_id(@voice)} .msg-actions.is-open a.msg-action--download", visible: true)
    assert_match %r{/files/\d+/voice-note\.wav\z}, download[:href]
  end

  test "phone, dark: menu and reactions" do
    visit conversation_path(@chat)
    page.execute_script("localStorage.setItem('fc-dark', '1')")
    visit conversation_path(@chat)
    assert_selector "html.theme-dark"
    find("##{dom_id(@short)} .msg-body").click
    assert_menu_on_screen(find("##{dom_id(@short)} .msg-actions.is-open"))
    pill = open_pill(@short)
    shot("zchl-react-pill-dark")
    pill.find(".msg-react-quick", text: "❤️").click
    assert_selector "##{dom_id(@short)} .msg-reactions .msg-reaction", text: "❤️"
    shot("zchl-reaction-shown-dark")
  ensure
    page.execute_script("localStorage.removeItem('fc-dark')") rescue nil
  end

  test "older app builds without native downloads use the file-store link" do
    page.driver.browser.execute_cdp("Network.setUserAgentOverride",
                                    userAgent: APP_USER_AGENT.sub(" NativeDownloads;", ""))
    visit conversation_path(@chat)
    page.execute_script(<<~JS)
      document.addEventListener("click", e => { if (e.target.closest("a")) e.preventDefault() })
    JS
    find("##{dom_id(@photo)} .msg-more").click
    link = find("##{dom_id(@photo)} .msg-actions.is-open a.msg-action--download")
    link.click
    assert_match %r{/rails/active_storage/}, link[:href]
  ensure
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: APP_USER_AGENT)
  end

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  # Fully on screen, below the chat's header, nothing cut off at either edge.
  def assert_menu_on_screen(menu)
    box = page.evaluate_script(<<~JS, menu)
      (el => { const r = el.getBoundingClientRect(); const h = document.querySelector(".msg-thread-head").getBoundingClientRect();
               return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, w: document.documentElement.clientWidth, vh: innerHeight, head: h.bottom } })(arguments[0])
    JS
    assert_operator box["left"], :>=, 0, "menu starts on screen (#{box.inspect})"
    assert_operator box["right"], :<=, box["w"], "menu ends on screen (#{box.inspect})"
    assert_operator box["top"], :>=, box["head"], "menu is below the chat header (#{box.inspect})"
    assert_operator box["bottom"], :<=, box["vh"], "menu is above the bottom of the screen (#{box.inspect})"
  end

  # React in the open menu pops up the pill of quick reactions, on screen.
  def open_pill(message)
    find("##{dom_id(message)} .msg-actions.is-open .msg-action--react").click
    pill = find("##{dom_id(message)} .msg-react-pill", visible: true)
    sleep 0.25 # let the pop-in finish before measuring
    box = page.evaluate_script("(el => { const r = el.getBoundingClientRect(); return { l: r.left, r: r.right, t: r.top, b: r.bottom, w: document.documentElement.clientWidth, h: innerHeight } })(arguments[0])", pill)
    assert box["l"] >= 0 && box["r"] <= box["w"] && box["t"] >= 0 && box["b"] <= box["h"], "pill on screen (#{box.inspect})"
    pill
  end

  def long_press(selector)
    el = find(selector)
    rect = page.evaluate_script("(el => { const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 } })(arguments[0])", el)
    point = { x: rect["x"], y: rect["y"] }
    browser = page.driver.browser
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ point ])
    sleep 0.7
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
  end

  def shot(name)
    dir = ENV["SHOT_DIR"]
    return if dir.blank?

    sleep 0.4 # let fades finish
    page.save_screenshot(File.join(dir, "390-#{name}.png"))
  end

  # A small solid-colour PNG so the photo renders.
  def png(shade)
    require "zlib"
    width, height = 240, 180
    rows = Array.new(height) { "\x00" + ([ shade.chr, 140.chr, 200.chr ].join * width) }.join
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1a\n".b + chunk.("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate(rows)) + chunk.("IEND", "")
  end

  # Three seconds of a quiet tone, so the browser really plays it.
  def wav
    rate = 8000
    samples = (0...(rate * 3)).map { |i| (Math.sin(2 * Math::PI * 440 * i / rate) * 2000).to_i }.pack("s<*")
    "RIFF".b + [ 36 + samples.bytesize ].pack("V") + "WAVEfmt ".b +
      [ 16, 1, 1, rate, rate * 2, 2, 16 ].pack("VvvVVvv") + "data".b + [ samples.bytesize ].pack("V") + samples
  end
end
