# frozen_string_literal: true

require "test_helper"

# The Daily Breath prompt (one question a day the community answers) and
# milestone badges (awarded on activity, worn on the profile).
class DailyPromptAndBadgesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @user = User.create!(username: "dp_user", email: "dp_user@example.com",
                         password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "DP Room", description: "x")
    sign_in @user
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "the feed shows the daily breath card until you've posted" do
    get feed_path
    assert_response :success
    assert_match "What breath do you have today?", response.body
    assert_match "Breathe it out", response.body

    Post.create!(user: @user, room: @room, title: "Answered it",
                 content: "Body", status: :published, moderation_status: :approved)
    get feed_path
    assert_match "You breathed today", response.body
  end

  test "publishing a first breath awards First Breath and notifies" do
    perform_enqueued_jobs do
      Post.create!(user: @user, room: @room, title: "My first",
                   content: "Body", status: :published, moderation_status: :approved)
    end

    assert @user.user_badges.exists?(slug: "first_breath"), "first_breath badge expected"
    note = Notification.badge_earned.find_by(user: @user)
    assert note, "badge notification expected"
    assert_match(/First Breath/, note.message)

    get user_path(@user.username)
    assert_match "First Breath", response.body
  end

  test "a perfect game round awards Perfect Round" do
    perform_enqueued_jobs do
      @user.game_attempts.create!(kind: :bible_quiz, score: 5, max_score: 5)
    end
    assert @user.user_badges.exists?(slug: "perfect_round")
  end

  test "badges are never awarded twice" do
    UserBadge.check!(@user.tap { |u| Post.create!(user: u, room: @room, title: "One",
                                                  content: "B", status: :published,
                                                  moderation_status: :approved) })
    assert_no_difference -> { UserBadge.count } do
      UserBadge.check!(@user)
    end
  end
end
