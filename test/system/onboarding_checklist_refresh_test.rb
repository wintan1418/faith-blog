# frozen_string_literal: true

require "application_system_test_case"

# Tester: set up the professional profile from the feed's "Make yourself at
# home" list, come back to the feed, and the step still showed as not done
# until the app was restarted. In the app the settings screens open on top of
# the feed, so the feed you come back to is the same page as before (or
# Turbo's saved copy of it). The list now updates live when a step changes,
# and reloads itself when it's shown from a saved copy.
class OnboardingChecklistRefreshTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  STEP = "#onboarding_checklist [data-step='professional']"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("checklist_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                                tour_completed_at: Time.current)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "the step ticks on the open feed when the professional profile is saved on another screen" do
    visit feed_path
    assert_selector "#{STEP}:not(.is-done)"
    assert_selector "turbo-cable-stream-source[connected]", minimum: 1, visible: false
    feed = current_window

    # The settings screen on top of the feed (the app's modal), here a second window.
    settings = open_new_window
    within_window(settings) do
      visit edit_settings_professional_path
      fill_in "Headline", with: "Teacher and worship leader"
      within("form", text: "Headline") { click_on "Save" }
      # Save closes the page (where it lands differs for the app and the web;
      # see ProfessionalProfileFlowTest).
      assert_no_current_path edit_settings_professional_path
    end
    assert_equal "Teacher and worship leader", @member.profile.reload.headline
    settings.close

    switch_to_window(feed)
    assert_selector "#{STEP}.is-done"
  end

  test "the step ticks when the feed comes back from Turbo's saved copy" do
    visit feed_path
    assert_selector "#{STEP}:not(.is-done)"

    within(STEP) { click_on "Set it up" }
    assert_current_path edit_settings_professional_path
    # Done somewhere else meanwhile (another screen, another device).
    @member.profile.update!(headline: "Teacher and worship leader")

    page.go_back # restores the saved copy of the feed
    assert_current_path feed_path
    assert_selector "#{STEP}.is-done"
  end
end
