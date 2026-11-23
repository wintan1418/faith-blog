# frozen_string_literal: true

require "application_system_test_case"

# On a phone the circle page was wider than the screen: the "breathe" box and
# the prayer list pushed the page sideways (Nov 2026 crash hunt).
class CirclePageWidthTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup { ENV["AI_MODERATION_STUB"] = "1" }
  teardown do
    Warden.test_reset!
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "the circle page fits a phone screen" do
    owner = create_member("circle_width_owner", welcomed_at: Time.current, tour_completed_at: Time.current,
                                                onboarding_dismissed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    circle = Circle.create!(name: "Tuesday Cell Group", owner: owner, description: "Our small group")
    circle.circle_memberships.find_or_create_by!(user: owner) { |m| m.role = :owner }
    CirclePrayer.create!(circle: circle, user: owner, title: "For my mother's healing", details: "She is in hospital this week.")

    page.driver.browser.manage.window.resize_to(390, 844)
    login_as owner, scope: :user
    visit circle_path(circle)
    assert_text "Prayer list"

    overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator overflow, :<=, 0, "the page scrolls sideways by #{overflow}px"
  end
end
