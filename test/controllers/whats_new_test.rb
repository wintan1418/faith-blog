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

  test "the professional release has buttons to the profile, LinkedIn import and chess" do
    Announcement.releases.delete_all
    Announcement.create!(kind: :release, title: "New in Brethreign · Professional profiles",
                         body: "💼 Your professional profile — Tabs [[professional]]\n🔗 Import from LinkedIn — Upload [[linkedin]]\n♞ The chess ladder — Climb [[chess]]")
    get feed_path

    assert_select "dialog.wn a[href=?]", user_path(@user.username, tab: "professional"), text: "Open my professional profile"
    assert_select "dialog.wn a[href=?]", new_settings_linkedin_import_path, text: "Import from LinkedIn"
    assert_select "dialog.wn a[href=?][data-action='whats-new#markSeen']", games_chess_path, text: "Play the ladder"
  end

  test "the portfolio release has an Add your work button" do
    Announcement.releases.delete_all
    Announcement.create!(kind: :release, title: "New in Brethreign · Portfolio", body: "🗂️ Your portfolio — Show your work [[portfolio]]")
    get feed_path
    assert_select "dialog.wn a[href=?]", new_settings_portfolio_item_path, text: "Add your work"
  end

  test "the Open to and card release links to the Open to settings and my card" do
    Announcement.releases.delete_all
    Announcement.create!(kind: :release, title: "New in Brethreign · Open to",
                         body: "🟢 Say what you're open to — Rings [[open_to]]\n🪪 Your business card — QR [[card]]")
    get feed_path
    assert_select "dialog.wn a[href=?]", edit_settings_professional_path(anchor: "open-to"), text: "Choose what I'm open to"
    assert_select "dialog.wn a[href=?]", card_path(@user.username), text: "See my card"
  end
end
