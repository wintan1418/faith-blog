# frozen_string_literal: true

require "test_helper"

class WaitlistJobsTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  IOS = "https://apps.apple.com/app/brethreign/id123"

  def with_ios_live
    old = ENV["IOS_STORE_URL"]
    ENV["IOS_STORE_URL"] = IOS
    yield
  ensure
    ENV["IOS_STORE_URL"] = old
  end

  test "launch emails everyone waiting for that platform once" do
    ios = AppWaitlistEntry.create!(email: "a@example.com", platform: "ios")
    both = AppWaitlistEntry.create!(email: "b@example.com", platform: "both")
    android = AppWaitlistEntry.create!(email: "c@example.com", platform: "android")

    with_ios_live do
      assert_emails 2 do
        WaitlistLaunchJob.perform_now("ios")
      end
      assert ios.reload.ios_notified_at
      assert both.reload.ios_notified_at
      assert_nil android.reload.ios_notified_at

      assert_no_emails { WaitlistLaunchJob.perform_now("ios") }
    end
  end

  test "launch does nothing until the store link is set" do
    AppWaitlistEntry.create!(email: "d@example.com", platform: "android")
    old = ENV["ANDROID_STORE_URL"]
    ENV["ANDROID_STORE_URL"] = nil
    assert_no_emails { WaitlistLaunchJob.perform_now("android") }
  ensure
    ENV["ANDROID_STORE_URL"] = old
  end

  test "confirmation is sent once, and counts as the launch email when the app is out" do
    entry = AppWaitlistEntry.create!(email: "e@example.com", platform: "both")
    with_ios_live do
      assert_emails 1 do
        WaitlistConfirmationJob.perform_now(entry.id)
      end
      entry.reload
      assert entry.confirmed_at
      assert entry.ios_notified_at
      assert_nil entry.android_notified_at
      assert_no_emails { WaitlistConfirmationJob.perform_now(entry.id) }
    end
  end
end
