# frozen_string_literal: true

require "test_helper"

# Two Android tester cards:
#  - Saving the Edit Professional Profile page left you on it (it redirected
#    back to itself). It now closes and returns to your professional profile.
#  - "Set up your professional profile" on the feed's getting-started list
#    only ticked after restarting the app: the feed was shown from a saved
#    copy. The list now reloads itself (onboarding#checklist) and is told to
#    when a step changes elsewhere.
class ProfessionalProfileFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Turbo::Broadcastable::TestHelper

  APP_UA = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android; Mozilla/5.0 (Linux; Android 16)"

  setup do
    @user = User.create!(username: "pro_member", email: "pro_member@example.com", password: "password123",
                         password_confirmation: "password123")
    sign_in @user
  end

  test "saving the professional profile on the web returns to the professional profile" do
    patch settings_professional_path, params: { profile: { headline: "Teacher and worship leader" } }

    assert_redirected_to user_path(@user.username, tab: "professional")
    assert_equal "Professional profile saved.", flash[:notice]
    assert_equal "Teacher and worship leader", @user.reload.profile.headline
  end

  test "saving the professional profile in the app closes the page" do
    patch settings_professional_path, params: { profile: { headline: "Nurse" } }, headers: { "User-Agent" => APP_UA }

    assert_response :redirect
    assert_match %r{/recede_historical_location}, response.location
  end

  test "your own profile is never shown from a saved copy, so it shows what you just saved" do
    get user_path(@user.username, tab: "professional")
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
  end

  test "the getting-started list can be reloaded on its own and shows the professional step done" do
    get onboarding_checklist_path
    assert_select "turbo-frame#onboarding_checklist_frame[target='_top'] [data-step='professional']:not(.is-done)"

    @user.profile.update!(headline: "Accountant")
    get onboarding_checklist_path
    assert_select "turbo-frame#onboarding_checklist_frame [data-step='professional'].is-done"
  end

  test "the feed's list is in a frame that reloads itself and listens for changes" do
    get feed_path
    assert_select "turbo-frame#onboarding_checklist_frame[data-controller='stale-frame']" \
                  "[data-stale-frame-url-value=?]", onboarding_checklist_path
    assert_select "turbo-cable-stream-source", minimum: 1
  end

  test "setting up the professional profile tells an open feed to reload its list" do
    streams = capture_turbo_stream_broadcasts([ @user, :onboarding ]) do
      @user.experiences.create!(title: "Teacher", organization: "Grace School", start_on: Date.new(2020, 1, 1))
    end
    refresh = streams.find { |s| s["target"] == "onboarding_checklist_frame" }
    assert refresh, "no refresh broadcast"
    assert_includes refresh.to_html, %(src="#{onboarding_checklist_path}")

    streams = capture_turbo_stream_broadcasts([ @user, :onboarding ]) { @user.profile.update!(headline: "Teacher") }
    assert(streams.any? { |s| s["target"] == "onboarding_checklist_frame" })
  end

  test "no refresh is sent once the list is hidden" do
    @user.update_column(:onboarding_dismissed_at, Time.current)
    streams = capture_turbo_stream_broadcasts([ @user, :onboarding ]) { @user.profile.update!(headline: "Teacher") }
    assert_empty streams
  end
end
