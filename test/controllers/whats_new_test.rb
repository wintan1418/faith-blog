# frozen_string_literal: true

require "test_helper"

# The "What's new" pop-up: one slide per line, shown once per person.
class WhatsNewTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "wn_user", email: "wn_user@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    @user.update_column(:created_at, 1.week.ago)
    Announcement.releases.delete_all
    @release = Announcement.create!(kind: :release, title: "New in Brethreign",
                                    body: "🎂 Birthdays — Celebrate your brethren\n- 💼 Professional profile: Show what you do\nPlain line")
    sign_in @user
  end

  test "each line becomes a slide with an emoji, title and description" do
    slides = @release.slides

    assert_equal [ "🎂", "💼", "✨" ], slides.map(&:emoji)
    assert_equal [ "Birthdays", "Professional profile", "Plain line" ], slides.map(&:title)
    assert_equal "Celebrate your brethren", slides.first.text
  end

  test "shows until seen, then never again" do
    get feed_path
    assert_select "dialog.wn .wn-slide", count: 3

    post seen_whats_new_path(@release)
    assert_response :no_content

    get feed_path
    assert_select "dialog.wn", count: 0
  end

  test "brand-new members don't get older releases" do
    @release.update_column(:published_at, 1.month.ago)
    get feed_path

    assert_select "dialog.wn", count: 0
  end
end
