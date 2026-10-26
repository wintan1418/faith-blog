# frozen_string_literal: true

require "test_helper"

class ExperienceTest < ActiveSupport::TestCase
  setup { @user = User.create!(username: "pro_user", email: "pro_user@example.com", password: test_password) }

  test "month fields store the first of the month and show LinkedIn-style dates" do
    role = @user.experiences.create!(title: "Nurse", organization: "LUTH", start_month: "2022-03", end_month: "2024-05")

    assert_equal Date.new(2022, 3, 1), role.start_on
    assert_equal "Mar 2022 – May 2024", role.date_range
    assert_equal "2 yrs 3 mos", role.duration
  end

  test "a current role has no end date and reads Present" do
    role = @user.experiences.create!(title: "Pastor", organization: "Grace Chapel", start_month: "2020-01", end_month: "2021-01", current: true)

    assert_nil role.end_on
    assert_match "– Present", role.date_range
  end

  test "end must come after start" do
    role = @user.experiences.new(title: "X", organization: "Y", start_month: "2024-05", end_month: "2023-01")

    assert_not role.valid?
  end

  test "headline falls back to the current role" do
    @user.experiences.create!(title: "Nurse", organization: "LUTH", start_month: "2022-03", current: true)

    assert_equal "Nurse at LUTH", @user.reload.professional_headline
    @user.profile.update!(headline: "Healing hands")
    assert_equal "Healing hands", @user.reload.professional_headline
  end

  test "skills come from a comma list, tidied and de-duplicated" do
    @user.profile.update!(skills_list: " Nursing, public speaking ,Nursing,, Counselling ")

    assert_equal [ "Nursing", "public speaking", "Counselling" ], @user.profile.reload.skills
  end

  test "deleting the account removes the professional profile" do
    @user.experiences.create!(title: "Nurse", organization: "LUTH", start_month: "2022-03", current: true)
    @user.educations.create!(school: "UNILAG")

    assert_difference -> { Experience.count + Education.count }, -2 do
      @user.destroy!
    end
  end
end
