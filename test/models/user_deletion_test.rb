# frozen_string_literal: true

require "test_helper"

# Account deletion must always succeed (App Store guideline 5.1.1(v), and
# users' right to leave). Every table that points at users needs a rule.
class UserDeletionTest < ActiveSupport::TestCase
  def make_user(suffix = SecureRandom.hex(4))
    User.create!(
      username: "user_#{suffix}",
      email: "user_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_post(author)
    Post.create!(
      user: author,
      room: Room.create!(name: "Room #{SecureRandom.hex(4)}", description: "x"),
      title: "Test post #{SecureRandom.hex(4)}",
      content: "Body of the test post.",
      status: :published
    )
  end

  test "a user with activity across the app can delete their account" do
    leaving = make_user
    other = make_user
    post = make_post(other)

    # Notifications this user caused for someone else
    notification = Notification.create!(
      user: other, actor: leaving, notifiable: post,
      notification_type: Notification.notification_types.keys.first
    )
    # Mentioned by someone else
    Mention.create!(user: leaving, mentionable: post, mentioned_by: other)

    # Prayer Circles: owns one, and takes part in someone else's
    Circle.create!(owner: leaving, name: "Mine")
    their_circle = Circle.create!(owner: other, name: "Theirs")
    CircleMembership.create!(circle: their_circle, user: leaving)
    CircleBreath.create!(circle: their_circle, user: leaving, body: "Peace to you all")
    their_prayer = CirclePrayer.create!(circle: their_circle, user: other, title: "Please pray")
    CirclePrayerAmen.create!(circle_prayer: their_prayer, user: leaving)
    CirclePrayer.create!(circle: their_circle, user: leaving, title: "My request")

    # Staff records that should outlive the account
    log = ModerationLog.create!(moderator: leaving, target: post, action: "feature")
    broadcast = Broadcast.create!(
      sender: leaving, subject: "Hello brethren",
      body: "Grace and peace to you all. We are glad you are here. Keep breathing together this week."
    )

    assert_difference -> { User.count }, -1 do
      leaving.destroy!
    end

    assert_nil notification.reload.actor, "notification stays for the recipient, actor cleared"
    assert_nil log.reload.moderator, "moderation log is kept for the audit trail"
    assert_nil broadcast.reload.sender, "broadcast history is kept"
    assert_equal 0, their_prayer.reload.amens_count
    assert_equal 0, CircleBreath.where(circle: their_circle).count
    assert Circle.exists?(their_circle.id), "other people's circles are untouched"
  end

  test "a follower who leaves doesn't break the followed user's notifications" do
    follower = make_user
    followed = make_user
    notification = Notification.create!(
      user: followed, actor: follower, notifiable: follower, notification_type: :new_follower
    )

    follower.destroy!

    assert_nil notification.reload.actor
    assert_equal Rails.application.routes.url_helpers.notifications_path, notification.target_path
    assert_match "Someone", notification.message
  end
end
