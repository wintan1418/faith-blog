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

  test "is skipped when the user has email notifications disabled" do
    @user.update_column(:email_notifications_enabled, false)
    mail = WeeklyDigestMailer.with(user: @user).weekly_digest
    # ActionMailer::MessageDelivery wraps an empty Mail::Message when the
    # action returned without calling `mail`. Check there's no recipient.
    assert_nil mail.to
  end
end
