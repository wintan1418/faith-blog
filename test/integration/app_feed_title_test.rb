# frozen_string_literal: true

require "test_helper"

# In the apps the native top bar shows the page title; on the Feed the app shows the logo instead.
class AppFeedTitleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the feed's title in the app is blank: the app shows the logo instead" do
    sign_in create_member("title_member", tour_completed_at: Time.current)
    get feed_path, headers: { "User-Agent" => "Brethreign/1.0.9; Hotwire Native iOS; Turbo Native iOS" }
    assert_select "title", "\u200B"
  end
end
