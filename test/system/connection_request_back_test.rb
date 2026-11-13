# frozen_string_literal: true

require "application_system_test_case"

# Tester: open Connection Requests, tap a requester, accept on their profile,
# go back: the request still showed Accept / Decline until a refresh. Going
# back restored Turbo's snapshot of the page from before the accept.
class ConnectionRequestBackTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @receiver = create_member("req_receiver", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                              tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @sender = create_member("req_sender")
    [ @receiver, @sender ].each do |user|
      user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello there.", occupation: "Builder",
                                 whatsapp_number: "+2348012345678", email: user.email)
    end
    ConnectionRequest.create!(sender: @sender, receiver: @receiver)
    login_as @receiver, scope: :user
  end

  teardown { Warden.test_reset! }

  test "a request accepted on the requester's profile is gone when you go back" do
    visit connection_requests_path
    within("#connection_requests_received") do
      assert_text "wants to know you more"
      click_on @sender.display_name
    end

    click_on "Accept Request"
    assert_text "You're now connected"

    page.go_back
    assert_current_path connection_requests_path
    within("#connection_requests_received") do
      assert_text "No pending requests."
      assert_no_text @sender.display_name
    end
  end
end
