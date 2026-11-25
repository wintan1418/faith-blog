# frozen_string_literal: true

require "test_helper"

class SecurityCodeTest < ActiveSupport::TestCase
  include AccountSecurityHelpers

  setup { @user, = security_member("code_owner", verified: false) }

  test "codes are six digits, stored only as a hash, and work once" do
    issued = SecurityCode.issue!(user: @user, purpose: :verify_email, link: true)
    assert_match(/\A\d{6}\z/, issued.code)
    assert_not_includes issued.record.code_digest, issued.code
    assert_not_equal issued.link_token, issued.record.link_digest

    assert SecurityCode.check(user: @user, purpose: :verify_email, code: issued.code).ok?
    assert_equal :expired, SecurityCode.check(user: @user, purpose: :verify_email, code: issued.code).status
  end

  test "a code from another purpose or member never matches" do
    issued = SecurityCode.issue!(user: @user, purpose: :sign_in)
    other, = security_member("code_other")
    assert_equal :expired, SecurityCode.check(user: other, purpose: :sign_in, code: issued.code).status
    assert_equal :expired, SecurityCode.check(user: @user, purpose: :verify_email, code: issued.code).status
  end

  test "codes expire after ten minutes" do
    issued = SecurityCode.issue!(user: @user, purpose: :verify_email)
    travel 11.minutes
    assert_equal :expired, SecurityCode.check(user: @user, purpose: :verify_email, code: issued.code).status
  end

  test "five wrong guesses kill the code" do
    issued = SecurityCode.issue!(user: @user, purpose: :verify_email)
    wrong = issued.code == "000000" ? "111111" : "000000"
    4.times { assert_equal :wrong, SecurityCode.check(user: @user, purpose: :verify_email, code: wrong).status }
    assert_equal :too_many, SecurityCode.check(user: @user, purpose: :verify_email, code: wrong).status
    assert_equal :expired, SecurityCode.check(user: @user, purpose: :verify_email, code: issued.code).status
  end

  test "an earlier code still works after a resend (slow email)" do
    first = SecurityCode.issue!(user: @user, purpose: :verify_email)
    travel 61.seconds
    second = SecurityCode.issue!(user: @user, purpose: :verify_email)
    assert SecurityCode.check(user: @user, purpose: :verify_email, code: first.code).ok?
    # Using one retires the rest.
    assert_equal :expired, SecurityCode.check(user: @user, purpose: :verify_email, code: second.code).status
  end

  test "resending waits a minute, and at most six an hour per member" do
    SecurityCode.issue!(user: @user, purpose: :verify_email)
    error = assert_raises(SecurityCode::RateLimited) { SecurityCode.issue!(user: @user, purpose: :verify_email) }
    assert_operator error.retry_in, :<=, 60

    5.times do
      travel 61.seconds
      SecurityCode.issue!(user: @user, purpose: :verify_email)
    end
    travel 61.seconds
    assert_raises(SecurityCode::RateLimited) { SecurityCode.issue!(user: @user, purpose: :verify_email) }
    travel 1.hour
    assert SecurityCode.issue!(user: @user, purpose: :verify_email)
  end

  test "one IP can't send codes to many accounts" do
    SecurityCode::MAX_SENDS_PER_IP_HOUR.times do |i|
      member, = security_member("ip_spray_#{i}", verified: false)
      SecurityCode.issue!(user: member, purpose: :verify_email, ip: "203.0.113.9")
    end
    assert_raises(SecurityCode::RateLimited) { SecurityCode.issue!(user: @user, purpose: :verify_email, ip: "203.0.113.9") }
    assert SecurityCode.issue!(user: @user, purpose: :verify_email, ip: "203.0.113.10")
  end

  test "a one-tap link works once" do
    issued = SecurityCode.issue!(user: @user, purpose: :verify_email, link: true)
    assert_equal issued.record, SecurityCode.redeem_link(issued.link_token)
    assert_nil SecurityCode.redeem_link(issued.link_token)
    assert_nil SecurityCode.redeem_link("nonsense")
  end
end
