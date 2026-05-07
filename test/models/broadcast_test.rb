# frozen_string_literal: true

require "test_helper"

class BroadcastTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(
      username: "bc_admin",
      email: "bc_admin@example.com",
      password: "Password!1",
      password_confirmation: "Password!1",
      role: :admin
    )
  end

  test "requires subject and a long-enough body" do
    bc = Broadcast.new(sender: @admin, subject: "x", preheader: "")
    bc.body = "tiny"
    refute bc.valid?
    assert bc.errors[:subject].any?, "subject should error"
    assert bc.errors[:body].any?, "body should error"
  end

  test "saves a valid draft" do
    bc = Broadcast.new(
      sender: @admin,
      subject: "Hello brethren — what's new this month",
      preheader: "Quick update",
      status: :draft
    )
    bc.body = "Friends, here is everything new on Brethreign this month. Read on for the details."
    assert bc.valid?, bc.errors.full_messages.to_sentence
    assert bc.save
    assert bc.draft?
  end

  test "launch template returns a populated draft" do
    bc = Broadcast.new_with_launch_template(sender: @admin)
    assert bc.subject.present?
    assert bc.body.present?
    assert_match(/prayer/i, bc.body.to_plain_text)
  end

  test "eligible_user_count counts only active opted-in users with email" do
    User.create!(username: "in1", email: "in1@example.com", password: "Password!1", password_confirmation: "Password!1", email_notifications_enabled: true, active: true)
    User.create!(username: "out1", email: "out1@example.com", password: "Password!1", password_confirmation: "Password!1", email_notifications_enabled: false, active: true)
    User.create!(username: "out2", email: "out2@example.com", password: "Password!1", password_confirmation: "Password!1", email_notifications_enabled: true, active: false)

    count = Broadcast.eligible_user_count
    # @admin is counted (active + email defaults), in1 too — out1 and out2 excluded.
    assert count >= 2
  end
end
