# frozen_string_literal: true

require "test_helper"

# Admin → Members → a member: everything about them, private profile or not.
class AdminMemberPageTest < ActionDispatch::IntegrationTest
  setup do
    @boss = create_member("member_page_boss", role: :super_admin)
    @plain = create_member("member_page_plain")
    @shy = create_member("Victoria_Shy")
    @shy.profile.update!(public_profile: false, bio: "Quiet one", headline: "Nurse at City Hospital")
  end

  test "a super admin sees a private member's full page" do
    sign_in @boss
    get admin_user_path(@shy)
    assert_response :success
    assert_select "h1", text: "Victoria_Shy"
    assert_includes response.body, "Quiet one"
    assert_includes response.body, "Nurse at City Hospital"
    assert_includes response.body, "Private profile"
    assert_includes response.body, @shy.email
  end

  test "members can't open it" do
    sign_in @plain
    get admin_user_path(@shy)
    assert_redirected_to root_path
  end

  test "profile links work whatever the case of the username" do
    get user_path("victoria_shy")
    assert_response :success
    get user_path("Victoria_Shy")
    assert_response :success
  end
end
