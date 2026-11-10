# frozen_string_literal: true

require "test_helper"

class CanonicalHostAndIconsTest < ActionDispatch::IntegrationTest
  test "www sends every page to the bare domain, keeping the path" do
    host! "www.brethreign.com"
    get "/users/sign_in?x=1"
    assert_response :moved_permanently
    assert_equal "http://brethreign.com/users/sign_in?x=1", response.location

    post "/users/auth/google_oauth2"
    assert_response :permanent_redirect
    assert_equal "http://brethreign.com/users/auth/google_oauth2", response.location
  end

  test "the bare domain is served as usual" do
    get "/users/sign_in"
    assert_response :success
  end

  test "pages link the real favicon and icons" do
    get "/users/sign_in"
    assert_select "link[rel=icon][href='/favicon.ico']"
    assert_select "link[rel=icon][href='/favicon-96.png']"
    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png']"
    %w[favicon.ico favicon-96.png icon.png icon-192.png apple-touch-icon.png].each do |file|
      assert File.size(Rails.public_path.join(file)) > 500, "#{file} looks empty"
    end
  end
end
