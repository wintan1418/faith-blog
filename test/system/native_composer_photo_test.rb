# frozen_string_literal: true

require "application_system_test_case"

# "I add a picture and Breathe does nothing" in the Android app. The photo the
# picker hands over can be a temporary link that stops working while the
# person writes, so the upload failed on the phone and nothing reached us —
# no post, no message. The composer now copies the photo when it is picked
# (shrinking big camera shots) and says so when a post doesn't send.
class NativeComposerPhotoTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ] do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 900, pixelRatio: 2, touch: true })
  end

  setup do
    @member = create_member("photo_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    login_as @member, scope: :user
    @photo = Rails.root.join("tmp", "test_camera_photo.png")
    unless File.exist?(@photo)
      # A 3000×2000 picture, like a phone camera's (PNG keeps it dependency-free).
      require "zlib"
      width, height = 3000, 2000
      rows = Array.new(height) { |y| "\x00" + ([ (y % 256).chr, ((y / 8) % 256).chr, 120.chr ].join * width) }.join
      chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
      png = "\x89PNG\r\n\x1a\n".b + chunk.("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
            chunk.("IDAT", Zlib::Deflate.deflate(rows)) + chunk.("IEND", "")
      File.binwrite(@photo, png)
    end
  end

  teardown { Warden.test_reset! }

  test "a big camera photo posts, scaled down to at most 2560px" do
    open_composer
    write "Windy days. Stand firm, stand strong."
    attach_photo

    assert_difference -> { Post.count }, 1 do
      breathe
      assert_no_selector "dialog.fc-composer-dialog[open]", wait: 15
    end
    image = Post.order(:created_at).last.images.first
    assert image, "the photo was attached"
    image.analyze unless image.analyzed?
    assert_operator [ image.metadata["width"], image.metadata["height"] ].max, :<=, 2560
  end

  test "when the post can't be sent, it says so and keeps the words" do
    open_composer
    write "This one won't send."
    attach_photo
    page.driver.browser.network_conditions = { offline: true, latency: 0, throughput: 0 }
    begin
      assert_no_difference -> { Post.count } do
        breathe
        assert_selector ".fc-composer-send-error", text: "didn't send", wait: 10
      end
      assert_selector "dialog.fc-composer-dialog[open] trix-editor", text: "This one won't send."
    ensure
      page.driver.browser.network_conditions = { offline: false, latency: 0, throughput: -1 }
    end
  end

  private

  def open_composer
    visit feed_path
    assert_selector "body.hotwire-native"
    page.execute_script(%(document.querySelector("[data-action~='click->composer-modal#open']").click()))
    find("dialog.fc-composer-dialog trix-editor", visible: true)
    assert page.evaluate_async_script(<<~JS), "editor never loaded"
      const done = arguments[arguments.length - 1]
      const el = document.querySelector("dialog.fc-composer-dialog trix-editor")
      const wait = (n) => el.editor ? done(true) : n ? setTimeout(() => wait(n - 1), 100) : done(false)
      wait(50)
    JS
  end

  def write(text)
    page.execute_script("document.querySelector('dialog.fc-composer-dialog trix-editor').editor.insertString(arguments[0])", text)
  end

  def attach_photo
    find("dialog.fc-composer-dialog input[type=file][name='post[images][]']", visible: :all).attach_file(@photo, make_visible: true)
    assert_selector "dialog.fc-composer-dialog .fc-composer-previews img", wait: 10
    assert_no_selector "dialog.fc-composer-dialog [type=submit][aria-busy=true]", wait: 10
  end

  def breathe
    page.execute_script(<<~JS)
      const form = document.querySelector("dialog.fc-composer-dialog form")
      const button = form.querySelector("[data-composer-mode-target~='submit']") ||
        [...form.querySelectorAll("[type=submit]")].find(b => /breathe/i.test(b.textContent))
      button.click()
    JS
  end
end
