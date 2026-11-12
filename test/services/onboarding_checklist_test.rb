# frozen_string_literal: true

require "test_helper"

# Each getting-started step ticks itself from what the member really did.
class OnboardingChecklistTest < ActiveSupport::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @user = make_user("check_me")
    @other = make_user("check_other")
    @room = Room.create!(name: "Checklist Room", description: "x")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: "Pw-#{SecureRandom.hex(8)}")
  end

  def done(user = @user) = OnboardingChecklist.new(user.reload).steps.select(&:done?).map(&:key)

  def publish(user)
    Post.create!(user: user, room: @room, title: "A breath", content: "Grace and peace",
                 status: :published, moderation_status: :approved)
  end

  test "a brand-new member has nothing done" do
    checklist = OnboardingChecklist.new(@user)
    assert_equal [], done
    assert_equal 0, checklist.done_count
    assert_equal 7, checklist.total
    assert_equal :photo, checklist.next_step.key
    assert checklist.visible?
  end

  test "a profile photo ticks the photo step" do
    @user.profile.avatar.attach(io: StringIO.new(PNG), filename: "me.png", content_type: "image/png")
    @user.profile.save!
    assert_includes done, :photo
  end

  test "only a published breath counts" do
    Post.create!(user: @user, room: @room, title: "Draft", content: "Not yet", status: :draft)
    assert_not_includes done, :breath
    publish(@user)
    assert_includes done, :breath
  end

  test "joining a prayer chain or tapping Praying both count as praying" do
    post = publish(@other)
    @user.prayer_intercessions.create!(post: post)
    assert_includes done, :prayed

    third = make_user("check_third")
    Like.create!(user: third, likeable: post, reaction_type: :praying)
    assert_includes done(third), :prayed
  end

  test "an ordinary like is not praying" do
    Like.create!(user: @user, likeable: publish(@other), reaction_type: :love)
    assert_not_includes done, :prayed
  end

  test "joining a room ticks the room step" do
    @room.room_memberships.create!(user: @user)
    assert_includes done, :room
  end

  test "the Brethren Card counts only when complete" do
    @user.brethren_card.update_columns(church_or_assembly: "Grace Assembly")
    assert_not_includes done, :card
    @user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello", occupation: "Teacher",
                                whatsapp_number: "+2348012345678", email: @user.email)
    assert_includes done, :card
  end

  test "following someone, or sending or receiving an accepted connection, counts" do
    @user.active_follows.create!(following: @other)
    assert_includes done, :connected
    assert_not_includes done(@other), :connected # being followed isn't the member's own step

    ConnectionRequest.insert_all!([ { sender_id: @user.id, receiver_id: @other.id, status: 1, created_at: Time.current, updated_at: Time.current } ])
    assert_includes done(@other), :connected
  end

  test "completion is recorded once, then the list is never visible again" do
    finish_everything(@user)
    checklist = OnboardingChecklist.new(@user.reload)
    assert checklist.complete?
    assert checklist.record_completion!
    assert_not OnboardingChecklist.new(@user.reload).record_completion!
    assert_not OnboardingChecklist.new(@user).visible?
  end

  test "hiding the list makes it invisible" do
    @user.update_column(:onboarding_dismissed_at, Time.current)
    assert_not OnboardingChecklist.new(@user).visible?
  end

  test "step counts across members, for the admin dashboard" do
    @room.room_memberships.create!(user: @user)
    @room.room_memberships.create!(user: @other)
    @user.active_follows.create!(following: @other)
    members = User.where(id: [ @user.id, @other.id ])

    counts = OnboardingChecklist.step_counts(members).to_h
    assert_equal 2, counts["Join a room"]
    assert_equal 1, counts["Follow or connect with someone"]
    assert_equal 0, counts["Take your first breath"]
    assert_equal 0, OnboardingChecklist.all_steps_count(members)

    finish_everything(@user)
    assert_equal 1, OnboardingChecklist.all_steps_count(members)
  end

  def finish_everything(user)
    user.profile.update_columns(headline: "Teacher and choir leader")
    user.profile.avatar.attach(io: StringIO.new(PNG), filename: "me.png", content_type: "image/png")
    user.profile.save!
    publish(user)
    user.prayer_intercessions.find_or_create_by!(post: publish(@other))
    @room.room_memberships.find_or_create_by!(user: user)
    user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello", occupation: "Teacher",
                               whatsapp_number: "+2348012345678", email: user.email)
    user.active_follows.find_or_create_by!(following: @other)
  end

  test "a headline or a role ticks the professional step" do
    assert_not_includes done, :professional
    @user.profile.update!(headline: "Nurse and worship leader")
    assert_includes done, :professional
  end

  test "each step points to a blog guide that exists" do
    OnboardingChecklist::STEPS.each_key do |key|
      assert OnboardingChecklist.guide_slug(key), "no guide for #{key}"
    end
  end
end
