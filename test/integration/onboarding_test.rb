# frozen_string_literal: true

require "test_helper"

# First-run onboarding on the feed: the getting-started list and the
# first-visit tour, plus the admin Onboarding panel.
class OnboardingTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @user = make_user("onb_member")
    @other = make_user("onb_friend")
    @room = Room.create!(name: "Onboarding Room", description: "x")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  def finish_everything(user)
    user.profile.update_columns(headline: "Teacher and choir leader")
    user.profile.avatar.attach(io: StringIO.new(PNG), filename: "me.png", content_type: "image/png")
    user.profile.save!
    Post.create!(user: user, room: @room, title: "Hello", content: "Grace and peace", status: :published, moderation_status: :approved)
    request = Post.create!(user: @other, room: @room, title: "Pray", content: "Please pray", status: :published, moderation_status: :approved)
    user.prayer_intercessions.create!(post: request)
    @room.room_memberships.create!(user: user)
    user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello", occupation: "Teacher",
                               whatsapp_number: "+2348012345678", email: user.email)
    user.active_follows.create!(following: @other)
  end

  def make_user(name, **attrs)
    User.create!(username: name, email: "#{name}@example.com", password: "Pw-#{SecureRandom.hex(8)}", **attrs)
  end

  test "a new member sees the getting-started list with every step to do" do
    sign_in @user
    get feed_path
    assert_response :success

    assert_select "#onboarding_checklist" do
      assert_select ".fc-checklist-count", text: "0 of 7 done"
      assert_select ".fc-checklist-step", 7
      assert_select ".fc-checklist-step.is-done", 0
      assert_select ".fc-checklist-step.is-next[data-step=photo]"
      assert_select "a[href=?]", edit_settings_profile_path, text: "Add photo"
      assert_select "button[data-action='click->composer-modal#open']", text: "Breathe"
      assert_select "a[href=?]", rooms_path, text: "Browse rooms"
      assert_select "a[href=?]", edit_settings_brethren_card_path, text: "Fill it in"
      assert_select "a[href=?]", edit_settings_professional_path, text: "Set it up"
      assert_select "a[href=?]", blog_path
      assert_select "a[href=?]", people_path, text: "Find people"
      assert_select "form[action=?] button", onboarding_hide_path, text: "Hide for now"
    end
  end

  test "steps tick as the member does them" do
    @room.room_memberships.create!(user: @user)
    @user.active_follows.create!(following: @other)
    sign_in @user
    get feed_path

    assert_select ".fc-checklist-count", text: "2 of 7 done"
    assert_select ".fc-checklist-step.is-done[data-step=room]"
    assert_select ".fc-checklist-step.is-done[data-step=connected]"
    assert_select ".fc-checklist-step.is-done a", count: 0 # no button on a done step
  end

  test "Hide for now persists on the account" do
    sign_in @user
    post onboarding_hide_path, as: :turbo_stream
    assert_response :success
    assert_match 'action="remove"', response.body
    assert_match "onboarding_checklist", response.body
    assert @user.reload.onboarding_dismissed_at

    get feed_path
    assert_select "#onboarding_checklist", 0

    # Settings can bring it back.
    get edit_settings_account_path
    assert_select "form[action=?]", onboarding_show_path
    post onboarding_show_path
    assert_redirected_to feed_path
    get feed_path
    assert_select "#onboarding_checklist", 1
  end

  test "finishing every step shows one quiet celebration, then nothing" do
    finish_everything(@user)
    sign_in @user
    get feed_path
    assert_select "#onboarding_checklist", 0
    assert_select ".fc-checklist-done", text: /You're all set/
    assert @user.reload.onboarding_completed_at

    get feed_path
    assert_select ".fc-checklist-done", 0
    assert_select "#onboarding_checklist", 0
  end

  test "a member who already finished never sees the list, even if a step is undone" do
    @user.update_column(:onboarding_completed_at, 1.day.ago)
    sign_in @user
    get feed_path
    assert_select "#onboarding_checklist", 0
    assert_select ".fc-checklist-done", 0
  end

  test "the tour shows once, anchored to real parts of the feed" do
    sign_in @user
    get feed_path
    assert_select ".fc-tour[data-controller=tour][data-tour-finish-url-value=?]", onboarding_finish_tour_path
    assert_select ".fc-tour-pop[role=dialog]"
    steps = JSON.parse(css_select(".fc-tour").first["data-tour-steps-value"])
    assert_equal %w[composer prayer rooms bible discover], steps.map { |s| s["anchor"] }
    steps.each { |s| assert_select "[data-tour-anchor=?]", s["anchor"] }

    post onboarding_finish_tour_path
    assert_response :no_content
    assert @user.reload.tour_completed_at

    get feed_path
    assert_select ".fc-tour", 0
  end

  test "Take the tour again from Settings" do
    @user.update_column(:tour_completed_at, 1.day.ago)
    sign_in @user
    get edit_settings_account_path
    assert_select "form[action=?] button", onboarding_restart_tour_path, text: "Take the tour again"

    post onboarding_restart_tour_path
    assert_redirected_to feed_path
    assert_nil @user.reload.tour_completed_at
    get feed_path
    assert_select ".fc-tour", 1
  end

  test "signed-out visitors can't touch onboarding" do
    post onboarding_hide_path
    assert_redirected_to new_user_session_path
  end

  test "the admin dashboard shows how many members did each step" do
    admin = make_user("onb_admin", role: :admin)
    @room.room_memberships.create!(user: @user)
    sign_in admin
    get admin_root_path
    assert_response :success

    assert_select ".adash-section", text: "Onboarding"
    assert_select "#adash-onboarding .adash-card", 2
    assert_select "#adash-onboarding .adash-card:first-child li", 7
    room_row = css_select("#adash-onboarding .adash-card:first-child li").find { |li| li.text.include?("Join a room") }
    assert_equal "1", room_row.at_css("strong").text
    assert_equal "#{(100.0 / User.count).round}%", room_row.at_css("em").text
  end
end
