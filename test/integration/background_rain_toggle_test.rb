# frozen_string_literal: true

require "test_helper"

# Members can switch the background scripture rain off (and back on).
class BackgroundRainToggleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_rain", email: "ada-rain@example.com", password: pass, password_confirmation: pass)
  end

  test "rain is on by default and the switch is in settings and the account menu" do
    sign_in @ada
    get edit_settings_accent_path

    assert_select "#fc-rain[data-rain-on-value='true']"
    assert_select ".fc-setting-switch[role='switch'][aria-checked='true'][data-action~='rain-toggle#toggle']"
    assert_select ".fc-rain-menu-item[data-rain-toggle-url-value=?]", settings_background_rain_path
  end

  test "switching it off is saved and the rain stays off" do
    sign_in @ada
    patch settings_background_rain_path, params: { on: false }, as: :json

    assert_response :success
    assert_equal({ "on" => false }, response.parsed_body)
    assert_not @ada.reload.background_rain?

    get edit_settings_accent_path
    assert_select "#fc-rain[data-rain-on-value='false']"
    assert_select ".fc-setting-switch[aria-checked='false']"
  end

  test "works without JavaScript too" do
    sign_in @ada
    patch settings_background_rain_path(on: false)
    assert_redirected_to edit_settings_accent_path
    assert_not @ada.reload.background_rain?

    patch settings_background_rain_path(on: true)
    assert @ada.reload.background_rain?
  end

  test "guests keep the rain and can't change settings" do
    get root_path
    assert_select "#fc-rain[data-rain-on-value='true']"

    patch settings_background_rain_path, params: { on: false }, as: :json
    assert_response :unauthorized
  end
end
