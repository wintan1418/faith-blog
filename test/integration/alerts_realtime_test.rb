# frozen_string_literal: true

require "test_helper"

# Alerts: "Mark all read" (and marking one read) answer at once, without a refresh.
class AlertsRealtimeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_alerts", email: "ada-alerts@example.com", password: pass, password_confirmation: pass)
    @ben = User.create!(username: "ben_alerts", email: "ben-alerts@example.com", password: pass, password_confirmation: pass)
    @note = Notification.create!(user: @ada, actor: @ben, notifiable: @ben, notification_type: :new_follower)
    sign_in @ada
  end

  test "mark all read answers with an in-place page refresh" do
    post mark_all_read_notifications_path, as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(<turbo-stream action="refresh")
    assert_not_includes response.body, "request-id", "a request id would make Turbo ignore the refresh"
    assert_not @note.reload.unread?
  end

  test "mark one read answers with an in-place page refresh" do
    post mark_read_notification_path(@note), as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(<turbo-stream action="refresh")
    assert_not @note.reload.unread?
  end

  test "the page shows a compact mark-all button while there are unread alerts" do
    get notifications_path
    assert_select "form.fc-notifpage-markall-form button.fc-notifpage-markall", text: /Mark all read/
  end
end
