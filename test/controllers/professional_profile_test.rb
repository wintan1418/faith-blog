# frozen_string_literal: true

require "test_helper"

class ProfessionalProfileTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "pro_owner", email: "pro_owner@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    sign_in @user
  end

  test "add, edit and remove an experience" do
    post settings_experiences_path, params: { experience: { title: "Engineer", organization: "Paystack", start_month: "2022-03", current: "1" } }
    assert_redirected_to edit_settings_professional_path
    role = @user.experiences.sole

    patch settings_experience_path(role), params: { experience: { title: "Senior Engineer" } }
    assert_equal "Senior Engineer", role.reload.title

    delete settings_experience_path(role)
    assert_empty @user.experiences.reload
  end

  test "headline, skills and education show on the public profile" do
    patch settings_professional_path, params: { profile: { headline: "Engineer · Worship leader", skills_list: "Ruby, Mentoring" } }
    post settings_educations_path, params: { education: { school: "University of Lagos", qualification: "BSc", start_year: 2012, end_year: 2016 } }

    get user_path(@user.username)
    assert_select ".profile-headline", text: "Engineer · Worship leader"
    assert_select ".pro-card .pro-item-title", text: "University of Lagos"
    assert_select ".pro-skill", count: 2
  end

  test "you can't edit someone else's experience" do
    other = User.create!(username: "pro_other", email: "pro_other@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    role = other.experiences.create!(title: "Nurse", organization: "LUTH", start_month: "2022-03", current: true)

    patch settings_experience_path(role), params: { experience: { title: "Hacked" } }
    assert_response :not_found
    assert_equal "Nurse", role.reload.title
  end

  test "dismissing a suggestion removes the card and remembers it" do
    other = User.create!(username: "pro_suggested", email: "pro_suggested@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    post suggestion_dismissals_path(user_id: other.id), as: :turbo_stream

    assert_response :success
    assert_match %r{<turbo-stream action="remove" target="suggestion_user_#{other.id}">}, response.body
    assert @user.suggestion_dismissals.exists?(dismissed_user: other)
  end

  test "the public assembly shows on the profile" do
    patch settings_professional_path, params: { profile: { assembly: "Living Faith Chapel, Lagos" } }
    get user_path(@user.username)

    assert_select ".profile-assembly", text: /Living Faith Chapel/
  end
end
