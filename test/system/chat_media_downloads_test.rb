# frozen_string_literal: true

require "application_system_test_case"

# Trello #94: photos, documents and voice notes in a chat each show their own
# download arrow, so saving one doesn't mean opening it full screen first.
# Checked at phone size with the Android app's user agent.
class ChatMediaDownloadsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; NativeShare; NativeDownloads; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ] do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 900, pixelRatio: 2, touch: true })
  end

  setup do
    release = Announcement.maximum(:id).to_i
    @ada = create_member("ada_media", welcomed_at: Time.current, seen_release_id: release)
    @ben = create_member("ben_media", welcomed_at: Time.current, seen_release_id: release)
    @chat = Conversation.find_or_create_between!(@ada, @ben)

    @photos = @chat.messages.new(sender: @ada, body: "From Sunday")
    2.times { |i| @photos.images.attach(io: StringIO.new(png(80 + (i * 90))), filename: "Sunday #{i + 1}.png", content_type: "image/png") }
    @photos.save!
    @doc = @chat.messages.new(sender: @ada, body: "")
    @doc.documents.attach(io: StringIO.new("%PDF-1.4\n%%EOF\n"), filename: "Sermon notes.pdf", content_type: "application/pdf")
    @doc.save!
    @voice = @chat.messages.new(sender: @ada, body: "")
    @voice.voice_note.attach(io: StringIO.new("OggS voice"), filename: "voice-note.ogg", content_type: "audio/ogg")
    @voice.save!

    login_as @ben, scope: :user
  end

  teardown { Warden.test_reset! }

  test "every photo, document and voice note has a visible download arrow" do
    visit conversation_path(@chat)

    arrows = all(".msg-image-wrap a.msg-media-get.is-on-photo", minimum: 2)
    arrows.each { |a| assert_match %r{/inbox/\d+/messages/\d+/files/\d+/Sunday%20\d\.png\z}, a[:href] }
    assert_selector "a.msg-doc .msg-doc-get svg", visible: true
    assert_selector ".msg-voice-row a.msg-media-get[href$='/voice-note.ogg']", visible: true

    # The arrow sits inside the photo and is big enough to tap.
    box = page.evaluate_script(<<~JS)
      (() => { const a = document.querySelector(".msg-media-get.is-on-photo").getBoundingClientRect();
               const i = document.querySelector(".msg-image").getBoundingClientRect();
               return { inside: a.left >= i.left && a.right <= i.right && a.top >= i.top && a.bottom <= i.bottom, w: a.width } })()
    JS
    assert box["inside"], "the arrow sits on the photo"
    assert_operator box["w"], :>=, 32

    # The app saves the file itself, so the page keeps the real link (not the file-store one).
    page.execute_script("document.querySelector('.msg-media-get.is-on-photo').addEventListener('click', e => e.preventDefault())")
    first(".msg-media-get.is-on-photo").click
    assert_no_selector ".fc-lightbox", wait: 0.5
    # Still white while hovered or focused (site-wide link colours used to win).
    assert_equal "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.querySelector('.msg-media-get.is-on-photo')).color")
    assert_match %r{/files/}, first(".msg-media-get.is-on-photo")[:href]

    shot("94-chat-downloads-light")
    page.execute_script("localStorage.setItem('fc-dark', '1')")
    visit conversation_path(@chat)
    assert_selector "html.theme-dark"
    shot("94-chat-downloads-dark")
  ensure
    page.execute_script("localStorage.removeItem('fc-dark')") rescue nil
  end

  test "older app builds without native downloads use the file-store link" do
    page.driver.browser.execute_cdp("Network.setUserAgentOverride",
                                    userAgent: APP_USER_AGENT.sub(" NativeDownloads;", ""))
    visit conversation_path(@chat)
    page.execute_script(<<~JS)
      document.addEventListener("click", e => e.preventDefault())
    JS
    first(".msg-media-get.is-on-photo").click
    assert_match %r{/rails/active_storage/}, first(".msg-media-get.is-on-photo")[:href]
  ensure
    page.driver.browser.execute_cdp("Network.setUserAgentOverride", userAgent: APP_USER_AGENT)
  end

  private

  def shot(name)
    dir = ENV["SHOT_DIR"]
    page.save_screenshot(File.join(dir, "#{name}.png")) if dir.present?
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
end
