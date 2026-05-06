# frozen_string_literal: true

require "test_helper"

class UserRiskProfileTest < ActiveSupport::TestCase
  def make_user(suffix = SecureRandom.hex(4))
    User.create!(
      username: "user_#{suffix}",
      email: "user_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "new user gets a clear risk profile via after_create" do
    user = make_user
    assert user.risk_profile.present?
    assert user.risk_profile.clear?
    assert_equal 0.0, user.risk_profile.risk_score
  end

  test "elevated scope excludes clear users" do
    a = make_user
    b = make_user
    b.risk_profile.update!(risk_level: :watch)

    elevated_users = UserRiskProfile.elevated.pluck(:user_id)
    refute_includes elevated_users, a.id
    assert_includes elevated_users, b.id
  end

  test "at_least? compares risk_level rank" do
    user = make_user
    user.risk_profile.update!(risk_level: :restricted)

    assert user.risk_profile.at_least?(:watch)
    assert user.risk_profile.at_least?(:restricted)
    refute user.risk_profile.at_least?(:suspended)
  end
end
