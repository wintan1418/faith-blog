# frozen_string_literal: true

require "test_helper"

class ProfessionalStrengthTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "strength_user", email: "strength_user@example.com", password: "Pw-#{SecureRandom.hex(8)}")
  end

  test "a new member starts at zero with every step to do" do
    strength = ProfessionalStrength.new(@user)
    assert_equal 0, strength.score
    assert_equal "Starting", strength.level
    assert_equal strength.steps.size, strength.next_steps.size
  end

  test "points add up as the profile fills in" do
    @user.profile.update!(headline: "Nurse · Choir member", skills: %w[Care Triage Teaching Singing Admin],
                          assembly: "Grace Assembly", location: "Accra, Ghana",
                          bio: "Paediatric nurse in Accra. I sing in the choir and teach Sunday school.")
    @user.experiences.create!(title: "Nurse", organization: "Korle Bu", start_month: "2020-01", current: true)
    @user.educations.create!(school: "University of Ghana")

    strength = ProfessionalStrength.new(@user.reload)
    assert_equal 90, strength.score # everything except a photo
    assert_equal "All-star", strength.level
    assert_equal [ :photo ], strength.next_steps.map(&:key)
  end

  test "the skills step says how many you have so far" do
    @user.profile.update!(skills: %w[Ruby Rails])
    step = ProfessionalStrength.new(@user).steps.find { |s| s.key == :skills }
    assert_not step.done
    assert_equal "you have 2", step.hint
  end
end
