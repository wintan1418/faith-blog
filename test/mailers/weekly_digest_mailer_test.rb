# frozen_string_literal: true

require "test_helper"

class WeeklyDigestMailerTest < ActionMailer::TestCase
  setup do
    @user = User.create!(
      username: "digest_user",
      email: "digest@example.com",
      password: "Password!1",
      password_confirmation: "Password!1"
    )
  end

  test "renders subject + greeting + unsubscribe link" do
    mail = WeeklyDigestMailer.with(user: @user).weekly_digest
    assert_match(/Brethreign/i, mail.subject)
    assert_equal [ @user.email ], mail.to

    text = mail.text_part.body.to_s
    html = mail.html_part.body.to_s
    assert_match(/Hi #{@user.display_name}/i, text)
    assert_match(/Hi #{@user.display_name}/i, html)
    assert_match(/email\/unsubscribe\/weekly-digest/, text)
    assert_match(/email\/unsubscribe\/weekly-digest/, html)
  end

  test "includes new followers, badges, and answered prayers from the week" do
    ENV["AI_MODERATION_STUB"] = "1"
    follower = User.create!(username: "digest_fan", email: "fan@example.com",
                            password: "Password!1", password_confirmation: "Password!1")
    follower.active_follows.create!(following: @user)

    UserBadge.create!(user: @user, slug: "first_breath", awarded_at: 1.day.ago)

    room = Room.create!(name: "Digest Room", description: "x")
    prayer = Post.create!(user: @user, room: room, title: "Please pray",
                          content: "A need", status: :published, moderation_status: :approved,
                          prayer_status: :prayer_answered, prayer_answered_at: 1.day.ago,
                          published_at: 3.days.ago)
    PrayerIntercession.create!(user: follower, post: prayer)

    mail = WeeklyDigestMailer.with(user: @user).weekly_digest
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    assert_match(/New brethren/i, html)
    assert_match(/digest_fan/i, html)
    assert_match(/Milestones you earned/i, html)
    assert_match(/Prayers answered this week/i, html)
    assert_match(/Your prayer/i, html)
    assert_match(/Milestones you earned/i, text)
    assert_match(/Prayers answered this week/i, text)
  ensure
    ENV.delete("AI_MODERATION_STUB")
  end

  test "is skipped when the user has email notifications disabled" do
    @user.update_column(:email_notifications_enabled, false)
    mail = WeeklyDigestMailer.with(user: @user).weekly_digest
    # ActionMailer::MessageDelivery wraps an empty Mail::Message when the
    # action returned without calling `mail`. Check there's no recipient.
    assert_nil mail.to
  end
end
