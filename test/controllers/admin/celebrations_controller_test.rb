# frozen_string_literal: true

require "test_helper"

# Admin → Celebrations: create, edit, activate, delete, the calendar and the switch.
class Admin::CelebrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_member("cel_admin", role: :admin)
    sign_in @admin
  end

  test "members can't open it" do
    sign_in create_member("cel_plain")
    get admin_celebrations_path
    assert_redirected_to root_path
  end

  test "create a draft, edit it, activate, deactivate and delete" do
    get new_admin_celebration_path
    assert_response :success

    assert_difference -> { Celebration.count }, 1 do
      post admin_celebrations_path, params: { celebration: {
        name: "Thanksgiving (US) 2026", greeting_title: "Happy Thanksgiving", message: "Grateful for you",
        scripture_reference: "Psalm 100:4", scripture_text: "Enter into his gates with thanksgiving.",
        hashtag: "Thanksgiving", accent_color: "#b45309", emblem: "🍂", effect: "leaves",
        starts_local: "2026-11-26T00:00", ends_local: "2026-11-27T00:00", time_zone: "America/New_York",
        audience: "countries", country_codes: [ "", "US" ], share_card: "1"
      } }
    end
    c = Celebration.last
    assert_redirected_to admin_celebrations_path
    assert c.draft?
    assert_equal %w[US], c.country_codes
    assert_equal Time.utc(2026, 11, 26, 5), c.starts_at

    get admin_celebrations_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(c)}", text: /Thanksgiving \(US\) 2026/

    get edit_admin_celebration_path(c)
    assert_select ".cel-banner .cel-title", "Happy Thanksgiving"

    patch admin_celebration_path(c), params: { celebration: { greeting_title: "Happy Thanksgiving, brethren", audience: "everyone", country_codes: [ "" ] } }
    assert_redirected_to admin_celebrations_path
    assert_equal "Happy Thanksgiving, brethren", c.reload.greeting_title
    assert c.for_everyone?

    patch activate_admin_celebration_path(c)
    assert c.reload.live?
    patch deactivate_admin_celebration_path(c)
    assert c.reload.draft?

    assert_difference -> { Celebration.count }, -1 do
      delete admin_celebration_path(c)
    end
  end

  test "save and activate in one go; invalid input shows the form again" do
    post admin_celebrations_path, params: { activate: "1", celebration: {
      name: "New Year", greeting_title: "Happy New Year", starts_local: "2027-01-01T00:00", ends_local: "2027-01-02T00:00",
      time_zone: "Africa/Lagos", audience: "everyone", accent_color: "#0e5c43", effect: "confetti"
    } }
    assert Celebration.last.live?

    post admin_celebrations_path, params: { celebration: { name: "", greeting_title: "", starts_local: "2027-01-02T00:00", ends_local: "2027-01-01T00:00", time_zone: "Africa/Lagos", accent_color: "#0e5c43", effect: "none" } }
    assert_response :unprocessable_entity
    assert_select ".cel-admin-errors"
  end

  test "artwork can be uploaded" do
    post admin_celebrations_path, params: { celebration: {
      name: "Easter", greeting_title: "He is risen", starts_local: "2027-03-28T00:00", ends_local: "2027-03-30T00:00",
      time_zone: "Africa/Lagos", audience: "everyone", accent_color: "#b87a14", effect: "petals",
      artwork: fixture_file_upload("celebration_art.png", "image/png")
    } }
    assert Celebration.last.artwork.attached?
  end

  test "the calendar button adds drafts and the auto-activate switch flips" do
    post seed_presets_admin_celebrations_path
    assert_redirected_to admin_celebrations_path
    assert Celebration.where.not(preset_key: nil).any?
    assert Celebration.all.all?(&:draft?)

    patch auto_activate_admin_celebrations_path, params: { on: "1" }
    assert Celebration.auto_activate_presets?
    patch auto_activate_admin_celebrations_path, params: { on: "0" }
    assert_not Celebration.auto_activate_presets?
  end
end
