# frozen_string_literal: true

require "application_system_test_case"

# Signed-out web visitors can read, but a click further opens "Join Brethreign
# to keep reading" with Create account and Sign in.
class GuestGateSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    author = create_member("gate_sys_author")
    room = Room.create!(name: "Gate Sys Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Rejoice always", content: "Grace and peace " * 20,
                         status: :published, moderation_status: :approved)
  end

  teardown { Warden.test_reset! }

  test "a click on a post opens the dialog; Esc closes it; Sign in goes to sign in" do
    visit root_path(browse: 1)
    find(".home-feed-card-body", match: :first).click

    assert_selector "dialog.guest-gate[open]", text: "Join Brethreign to keep reading"
    assert_current_path root_path(browse: 1)

    find("body").send_keys(:escape)
    assert_no_selector "dialog.guest-gate[open]"

    find(".home-feed-actions a", match: :first).click # like
    within("dialog.guest-gate[open]") { click_link "Sign in" }
    # The like was on the feed, so sign-in will bring them back to it.
    assert_current_path new_user_session_path(return_to: "/?browse=1")
  end

  test "Look around first and the legal links stay open" do
    visit root_path
    click_link "Look around first"
    assert_current_path root_path(browse: 1)
    assert_no_selector "dialog.guest-gate[open]"

    visit root_path
    within(".welcome-footer") { click_link "Privacy" }
    assert_current_path privacy_path
  end

  test "the app waitlist on the welcome page submits without the gate" do
    visit root_path
    # A form shown long enough ago to look human (SignupGuard's minimum fill time).
    page.execute_script("document.querySelector('#get-the-app input[name=form_token]').value = arguments[0]",
                        SignupGuard.form_token(issued_at: 10.seconds.ago))
    within("#get-the-app") do
      fill_in "Email for the launch news", with: "gate.waitlist@example.com"
      choose "Android", allow_label_click: true
      click_button "Notify me"
      assert_text "You're on the list."
    end
    assert_no_selector "dialog.guest-gate[open]"
    assert_current_path root_path
    assert_equal "android", AppWaitlistEntry.find_by(email: "gate.waitlist@example.com")&.platform
  end

  test "members are never gated" do
    login_as create_member("gate_sys_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                               tour_completed_at: Time.current, onboarding_dismissed_at: Time.current), scope: :user
    visit post_path(@post)
    assert_no_selector "dialog.guest-gate", visible: :all
  end
end
