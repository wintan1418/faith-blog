# frozen_string_literal: true

require "test_helper"

class WaitlistMailerTest < ActionMailer::TestCase
  IOS = "https://apps.apple.com/app/brethreign/id123"
  ANDROID = "https://play.google.com/store/apps/details?id=com.brethreign"

  def with_stores(ios: nil, android: nil)
    old = ENV.values_at("IOS_STORE_URL", "ANDROID_STORE_URL")
    ENV["IOS_STORE_URL"] = ios
    ENV["ANDROID_STORE_URL"] = android
    yield
  ensure
    ENV["IOS_STORE_URL"], ENV["ANDROID_STORE_URL"] = old
  end

  test "joined, app not out yet: you're on the list, with a leave link" do
    entry = AppWaitlistEntry.create!(email: "ada@example.com", platform: "android")
    with_stores(ios: IOS) do
      mail = WaitlistMailer.with(entry: entry).joined
      assert_equal [ "ada@example.com" ], mail.to
      assert_equal "You're on the Brethreign app waitlist", mail.subject
      assert_includes mail.text_part.body.to_s, "as soon as Brethreign is on Android"
      assert_not_includes mail.text_part.body.to_s, IOS
      assert_includes mail.html_part.body.to_s, "/waitlist/leave/"
      assert mail.header["List-Unsubscribe"].to_s.include?("/waitlist/leave/")
    end
  end

  test "joined when their app is already out: the download link straight away" do
    entry = AppWaitlistEntry.create!(email: "bola@example.com", platform: "both")
    with_stores(ios: IOS) do
      mail = WaitlistMailer.with(entry: entry).joined
      assert_equal "You're on the list, and Brethreign is ready for you", mail.subject
      assert_includes mail.text_part.body.to_s, IOS
      assert_includes mail.text_part.body.to_s, "on Android too"
    end
  end

  test "launched carries the store link" do
    entry = AppWaitlistEntry.create!(email: "chi@example.com", platform: "both")
    with_stores(ios: IOS) do
      mail = WaitlistMailer.with(entry: entry, platform: "ios").launched
      assert_equal "Brethreign is now on the App Store", mail.subject
      assert_includes mail.html_part.body.to_s, IOS
      assert_includes mail.text_part.body.to_s, "On Android too?"
    end
  end
end
