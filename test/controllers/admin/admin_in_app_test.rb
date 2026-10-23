# frozen_string_literal: true

require "test_helper"

# The apps decide "still signed in?" from markers on <body>. Admin pages need them
# too, or opening Admin from the app looked like a sign-out.
class Admin::AdminInAppTest < ActionDispatch::IntegrationTest
  test "admin pages tell the app you're signed in" do
    admin = User.create!(username: "admin_app", email: "admin_app@example.com", password: "password123",
                         password_confirmation: "password123", role: :admin)
    sign_in admin
    get admin_root_path, headers: { "User-Agent" => "Brethreign/1.0.3; Hotwire Native Android; Turbo Native Android" }

    assert_response :success
    assert_select "body.hotwire-native[data-native-signed-in=true][data-native-admin=true]"
  end
end
