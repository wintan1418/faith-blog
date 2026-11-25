# frozen_string_literal: true

require "application_system_test_case"

# Making a page step by step (the address is suggested from the name and
# checked as you type), then following another page in place.
class OrgPagesSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i, created_at: 30.days.ago,
             tour_completed_at: Time.current }
    @member = create_member("pages_sys_member", **seen)
    owner = create_member("pages_sys_owner", **seen)
    @other = Page.create!(name: "Grace Chapel", handle: "gracechapelsys", category: "church", created_by: owner)
    @other.memberships.create!(user: owner, role: :owner, status: :active)
    login_as @member, scope: :user
  end

  teardown do
    Warden.test_reset!
    ENV.delete("AI_MODERATION_STUB")
  end

  test "create a page in steps" do
    visit new_org_page_path
    fill_in "Page name", with: "Hope Fellowship"
    find("label.pg-kind", text: "Fellowship").click
    click_on "Next"
    assert_equal "hopefellowship", find_field("page_handle").value, "suggested from the name"
    fill_in "page_handle", with: "support"
    assert_selector ".pg-hint-text.is-bad", text: /reserved/, wait: 5
    fill_in "page_handle", with: "hopefellowship"
    assert_selector ".pg-hint-text.is-good", wait: 5
    click_on "Next"
    assert_selector ".pg-logo-pick"
    click_on "Next"
    fill_in "About (optional)", with: "We pray and read together."
    click_on "Create page"
    assert_selector "h1.pg-name", text: "Hope Fellowship"
    assert Page.find_by_handle!("hopefellowship").owner?(@member)
  end

  test "follow and unfollow without leaving the page" do
    visit org_page_path(@other)
    find(".pg-actions .pg-follow", text: "Follow").click
    assert_selector ".pg-actions .pg-follow.is-following", text: "Following"
    assert @other.followed_by?(@member)
    find(".pg-actions .pg-follow.is-following").click
    assert_selector ".pg-actions .pg-follow.is-primary", text: "Follow"
    assert_not @other.followed_by?(@member)
  end
end
