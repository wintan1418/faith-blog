# frozen_string_literal: true

require "test_helper"

# Admin → Users: verification status, two-step login, recent sign-ins, and the
# audited resend-verification / reset-two-step actions.
class AdminSecurityTest < ActionDispatch::IntegrationTest
  include AccountSecurityHelpers

  setup do
    @admin, = security_member("sec_admin", role: :admin)
    @member, @member_password = security_member("sec_target", verified: false)
  end

  test "the members list shows verification and two-step status" do
    enable_two_factor_for(@admin)
    sign_in @admin
    get admin_users_path
    assert_select "td", /Email not verified/
    assert_select "td", /2FA on/
    assert_select "a[href=?]", security_admin_user_path(@member), "Security"
  end

  test "the security page shows recent sign-ins with rough places, never IPs" do
    password_sign_in(@member, @member_password, headers: { "CF-IPCountry" => "NG" })
    delete destroy_user_session_path
    sign_in @admin
    get security_admin_user_path(@member)
    assert_response :success
    assert_select "h2", "Recent sign-ins"
    assert_select "td", "Nigeria"
    assert_no_match(/127\.0\.0\.1/, response.body)
  end

  test "resend verification is audited" do
    sign_in @admin
    mails = mails_during { post resend_verification_admin_user_path(@member) }
    assert_redirected_to security_admin_user_path(@member)
    assert mails.any? { |m| m.to == [ @member.email ] && m.subject.include?("verification code") }
    assert SecurityEvent.exists?(user: @member, actor: @admin, kind: "admin_resent_verification")
    assert ModerationLog.exists?(moderator: @admin, action: "resent_email_verification", target: @member)
  end

  test "reset two-step login is audited, emailed, and only for members you outrank" do
    enable_two_factor_for(@member)
    sign_in @admin
    mails = mails_during { post reset_two_factor_admin_user_path(@member), params: { reason: "Lost phone, checked on a call" } }
    assert_not @member.reload.two_factor_enabled?
    assert mails.any? { |m| m.subject.start_with?("Two-step login is off") && m.html_part.body.to_s.include?("Brethreign team") }
    log = ModerationLog.find_by!(action: "reset_two_factor", target: @member)
    assert_equal "Lost phone, checked on a call", log.notes

    other_admin, = security_member("sec_admin_2", role: :admin)
    enable_two_factor_for(other_admin)
    post reset_two_factor_admin_user_path(other_admin)
    assert other_admin.reload.two_factor_enabled?, "an admin can't reset an equal's two-step login"
  end

  test "members can't reach it" do
    sign_in @member
    get security_admin_user_path(@admin)
    assert_redirected_to root_path
  end
end
