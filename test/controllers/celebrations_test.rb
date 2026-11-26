# frozen_string_literal: true

require "test_helper"

# Brethreign Celebrates on member pages: the feed banner, the strip, the
# one-time pop-up, dismissing, and country targeting.
class CelebrationsTest < ActionDispatch::IntegrationTest
  setup do
    Announcement.releases.delete_all
    @member = create_member("cel_member", welcomed_at: Time.current, tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @thanksgiving = Celebration.create!(name: "Thanksgiving", greeting_title: "Happy Thanksgiving", emblem: "🍂", effect: "leaves",
                                        message: "Grateful for every one of you.", hashtag: "Thanksgiving",
                                        scripture_reference: "Psalm 100:4", scripture_text: "Enter into his gates with thanksgiving.",
                                        starts_at: 1.hour.ago, ends_at: 1.day.from_now, status: :live)
    sign_in @member
  end

  def live_in(city)
    (@member.profile || @member.create_profile!).update_columns(city_id: cities(city).id)
  end

  test "the feed shows the banner with greeting, scripture and actions, plus the pop-up and logo accent" do
    get feed_path
    assert_response :success
    assert_select "#celebration-banner .cel-title", "Happy Thanksgiving"
    assert_select "#celebration-banner .cel-verse cite", /Psalm 100:4/
    assert_select "#celebration-banner [data-composer-modal-prefill-param*='#Thanksgiving']"
    assert_select "#celebration-banner [data-action='celebration#sendToFriend']"
    assert_select "#celebration-banner [data-testid='celebration-share-card']"
    assert_select "#celebration-banner .cel-fx.is-leaves"
    assert_select "dialog#celebration-popup[data-celebration-popup-key-value='#{@thanksgiving.popup_key}']"
    assert_select ".eg-brand .cel-logo-accent", "🍂"
    assert_select "#celebration-strip", count: 0
  end

  test "other main pages get the lighter strip; chats and settings don't" do
    get leaderboard_path
    assert_select "#celebration-strip strong", "Happy Thanksgiving"
    assert_select "#celebration-banner", count: 0

    get edit_user_registration_path
    assert_select "#celebration-strip", count: 0
    assert_select "#celebration-popup", count: 0
  end

  test "dismissing hides it for this occasion only" do
    post dismissals_path, params: { key: @thanksgiving.dismissal_key }
    assert_response :no_content

    get feed_path
    assert_select "#celebration-banner", count: 0
    assert_select ".cel-logo-accent", count: 0

    christmas = Celebration.create!(name: "Christmas", greeting_title: "Merry Christmas", starts_at: 1.hour.ago, ends_at: 1.day.from_now, status: :live)
    get feed_path
    assert_select "#celebration-banner .cel-title", "Merry Christmas"
    assert_not @member.reload.card_dismissed?(christmas.dismissal_key)
  end

  test "the pop-up shows once, and never over What's new" do
    post dismissals_path, params: { key: @thanksgiving.popup_key }
    get feed_path
    assert_select "#celebration-popup", count: 0
    assert_select "#celebration-banner"

    @member.update_column(:dismissed_cards, [])
    @member.update_column(:created_at, 1.week.ago)
    Announcement.create!(kind: :release, title: "New", body: "🎂 Birthdays — Celebrate")
    get feed_path
    assert_select "dialog.wn"
    assert_select "#celebration-popup", count: 0
  end

  test "country targeting: Thanksgiving for the US, not for Lagos" do
    @thanksgiving.update!(audience: :countries, country_codes: %w[US])

    live_in(:lagos)
    get feed_path
    assert_select "#celebration-banner", count: 0

    live_in(:houston)
    get feed_path
    assert_select "#celebration-banner .cel-title", "Happy Thanksgiving"
  end

  test "without a city, the connection's country is used" do
    @thanksgiving.update!(audience: :countries, country_codes: %w[US])
    get feed_path, headers: { "CF-IPCountry" => "US" }
    assert_select "#celebration-banner"
    get feed_path, headers: { "CF-IPCountry" => "NG" }
    assert_select "#celebration-banner", count: 0
  end

  test "drafts and finished occasions never show" do
    @thanksgiving.update!(status: :draft)
    get feed_path
    assert_select "#celebration-banner", count: 0

    @thanksgiving.update!(status: :live, starts_at: 2.days.ago, ends_at: 1.minute.ago)
    get feed_path
    assert_select "#celebration-banner", count: 0
  end

  test "a linked post gets a See the post link; no share card when switched off" do
    author = create_member("cel_page_author")
    greeting = Post.create!(user: author, title: "Happy Thanksgiving from Brethreign", content: "Grateful", status: :published, moderation_status: :approved)
    @thanksgiving.update!(post: greeting, share_card: false)
    get feed_path
    assert_select "#celebration-banner a[href='#{post_path(greeting)}']", /See the post/
    assert_select "#celebration-banner [data-testid='celebration-share-card']", count: 0
  end

  test "signed-out visitors see nothing" do
    sign_out @member
    get root_path
    assert_select "#celebration-banner, #celebration-strip, #celebration-popup", count: 0
  end
end
