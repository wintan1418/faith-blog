# frozen_string_literal: true

require "test_helper"

# Admin → App waitlist: emails are personal data, so admins only.
class AdminAppWaitlistTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_member("waitlist_admin", role: :admin)
    @member = create_member("waitlist_plain")
    AppWaitlistEntry.create!(email: "older@example.com", platform: "ios", source: "welcome", created_at: 2.days.ago)
    AppWaitlistEntry.create!(email: "newer@example.com", platform: "both", source: "welcome")
  end

  test "signed-out visitors and members can't see it" do
    get admin_app_waitlist_entries_path
    assert_redirected_to root_path
    get admin_app_waitlist_entries_path(format: :csv)
    assert_redirected_to root_path

    sign_in @member
    get admin_app_waitlist_entries_path
    assert_redirected_to root_path
    get admin_app_waitlist_entries_path(format: :csv)
    assert_redirected_to root_path
    assert_not_includes response.body, "older@example.com"
  end

  test "admins see the list, newest first, with counts by platform" do
    sign_in @admin
    get admin_app_waitlist_entries_path

    assert_response :success
    assert_select "[data-waitlist-count=total]", text: "2"
    assert_select "[data-waitlist-count=ios]", text: "1"
    assert_select "[data-waitlist-count=android]", text: "0"
    assert_select "[data-waitlist-count=both]", text: "1"
    assert_select "tbody tr td:first-child", count: 2 do |cells|
      assert_equal %w[newer@example.com older@example.com], cells.map { |c| c.text.strip }
    end
    assert_select "a[href=?]", admin_app_waitlist_entries_path(format: :csv), text: "Download CSV"
    # In the admin nav.
    assert_select ".admin-sidebar a[href=?]", admin_app_waitlist_entries_path, text: /App waitlist/
  end

  test "admins can download a CSV" do
    sign_in @admin
    get admin_app_waitlist_entries_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    rows = CSV.parse(response.body)
    assert_equal %w[email platform source signed_up_at updated_at], rows.first
    assert_equal %w[newer@example.com older@example.com], rows.drop(1).map(&:first)
  end

  test "admins can send the launch email once the store link is set" do
    sign_in @admin
    old = ENV["IOS_STORE_URL"]
    ENV["IOS_STORE_URL"] = "https://apps.apple.com/app/brethreign/id123"
    assert_enqueued_with(job: WaitlistLaunchJob, args: [ "ios" ]) do
      post notify_admin_app_waitlist_entries_path(platform: "ios")
    end
    assert_redirected_to admin_app_waitlist_entries_path
    assert_match(/to 2 people/, flash[:notice])
  ensure
    ENV["IOS_STORE_URL"] = old
  end

  test "members can't send the launch email" do
    sign_in @member
    assert_no_enqueued_jobs(only: WaitlistLaunchJob) do
      post notify_admin_app_waitlist_entries_path(platform: "ios")
    end
  end
end
