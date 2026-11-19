# frozen_string_literal: true

require "application_system_test_case"

# The bot guard on sign-up must be invisible to real people: a person fills
# the form at a human pace and lands in the app. Also checks the account
# settings form asks for the current password, at phone and desktop sizes.
class SignupAndAccountSafetyTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup { ENV["AI_MODERATION_STUB"] = "1" }
  teardown do
    Warden.test_reset!
    # The browser is shared with every desktop test: put its size back.
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  [ [ 390, 844 ], [ 1400, 1000 ] ].each do |width, height|
    test "a person can sign up through the real form at #{width}px" do
      page.driver.browser.manage.window.resize_to(width, height)
      visit new_user_registration_path

      honeypot = find("input[name='#{SignupGuard::HONEYPOT_PARAM}']", visible: :all)
      assert_not honeypot.visible?, "the honeypot must not be visible"
      assert_no_text "Leave this field empty"

      fill_in "Username", with: "real_person_#{width}"
      fill_in "Email", with: "real-person-#{width}@example.com"
      fill_in "Password", with: "Grace-and-peace-#{width}"
      sleep SignupGuard::MIN_FILL_TIME + 0.5 # a human pace
      click_button "Create account"

      assert_no_current_path new_user_registration_path, wait: 10
      assert User.exists?(email: "real-person-#{width}@example.com")
    end
  end

  test "account settings ask for the current password" do
    member = create_member("settings_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                              tour_completed_at: Time.current)
    login_as member, scope: :user
    visit edit_settings_account_path
    assert_field "Current Password"
    fill_in "Email", with: "elsewhere@example.com"
    click_button "Save Changes"
    assert_text "Current password can't be blank"
    assert_equal "settings_member@example.com", member.reload.email
  end
end
