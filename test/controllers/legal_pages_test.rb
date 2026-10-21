# frozen_string_literal: true

require "test_helper"

# The app stores link to these, so they must work for signed-out visitors.
class LegalPagesTest < ActionDispatch::IntegrationTest
  test "privacy policy is public" do
    get privacy_path
    assert_response :success
    assert_match "Privacy Policy", response.body
    assert_match "Delete Account", response.body
  end

  test "terms of use are public and ban objectionable content" do
    get terms_path
    assert_response :success
    assert_match "No tolerance for objectionable content", response.body
  end

  test "sign-up links to the terms and privacy policy" do
    get new_user_registration_path
    assert_select "a[href=?]", terms_path
    assert_select "a[href=?]", privacy_path
  end
end
