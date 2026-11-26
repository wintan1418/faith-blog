# frozen_string_literal: true

require "test_helper"

# Brethreign Celebrates: who sees an occasion, when, and what it says.
class CelebrationTest < ActiveSupport::TestCase
  def occasion(**attrs)
    Celebration.create!({ name: "Christmas", greeting_title: "Merry Christmas", starts_at: 1.hour.ago, ends_at: 1.day.from_now,
                          status: :live }.merge(attrs))
  end

  def member_in(city)
    create_member("cel_#{SecureRandom.hex(3)}").tap { |u| (u.profile || u.create_profile!).update_columns(city_id: cities(city).id) }
  end

  test "only live occasions inside their window are shown" do
    occasion(name: "Draft", status: :draft)
    occasion(name: "Later", starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    occasion(name: "Over", starts_at: 3.days.ago, ends_at: 1.minute.ago)
    assert_nil Celebration.current_for(nil)

    now = occasion(name: "Now")
    assert_equal now, Celebration.current_for(nil)
  end

  test "country occasions reach only their countries, and come before ones for everyone" do
    everyone = occasion(name: "Everyone")
    thanksgiving = occasion(name: "Thanksgiving", audience: :countries, country_codes: %w[US])

    assert_equal thanksgiving, Celebration.current_for(nil, country: "us")
    assert_equal everyone, Celebration.current_for(nil, country: "NG")
    assert_equal everyone, Celebration.current_for(nil, country: nil)
  end

  test "a countries audience needs at least one country, typed codes are added" do
    c = Celebration.new(name: "x", greeting_title: "x", starts_at: Time.current, ends_at: 1.day.from_now, audience: :countries)
    assert_not c.valid?
    assert_includes c.errors[:country_codes].join, "choose at least one country"

    c.country_list = "zm, RW, nonsense"
    c.country_codes = [ "", "NG" ]
    assert c.valid?, c.errors.full_messages.to_sentence
    assert_equal %w[NG ZM RW], c.country_codes
  end

  test "times from the admin form are read in the occasion's time zone" do
    c = Celebration.create!(name: "Thanksgiving", greeting_title: "Happy Thanksgiving", time_zone: "America/New_York",
                            starts_local: "2026-11-26T00:00", ends_local: "2026-11-27T00:00")
    assert_equal Time.utc(2026, 11, 26, 5), c.starts_at
    assert_equal "2026-11-26T00:00", c.reload.starts_local
  end

  test "the end must come after the start, and the zone and colour must be real" do
    c = Celebration.new(name: "x", greeting_title: "x", starts_at: Time.current, ends_at: 1.hour.ago, time_zone: "Mars/Base", accent_color: "green")
    assert_not c.valid?
    assert c.errors[:ends_at].any?
    assert c.errors[:time_zone].any?
    assert c.errors[:accent_color].any?
  end

  test "the verse text is filled in from the KJV when only a reference is given" do
    ScriptureVerse.create!(translation: "kjv", book: 19, chapter: 100, verse: 4,
                           text: "Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.")
    c = occasion(scripture_reference: "ps 100:4")
    assert_equal "Psalm 100:4", c.scripture_reference
    assert_match(/\AEnter into his gates with thanksgiving/, c.scripture_text)

    bad = Celebration.new(name: "x", greeting_title: "x", starts_at: Time.current, ends_at: 1.day.from_now, scripture_reference: "Hezekiah 4:1")
    assert_not bad.valid?
    assert bad.errors[:scripture_reference].any?
  end

  test "the post link accepts a full address or a slug" do
    author = create_member("cel_author")
    post = Post.create!(user: author, title: "Happy Thanksgiving from Brethreign", content: "Grateful", status: :published, moderation_status: :approved)
    c = occasion(post_link: "https://brethreign.com/posts/#{post.slug}?ref=x")
    assert_equal post, c.post

    c.update(post_link: "/posts/does-not-exist")
    assert c.errors[:post_link].any?
  end

  test "the greeting prefill carries the title, verse and hashtag" do
    c = occasion(greeting_title: "Happy Thanksgiving", emblem: "🍂", hashtag: "#Thanksgiving",
                 scripture_reference: "Psalm 100:4", scripture_text: "Enter into his gates with thanksgiving.")
    text = c.greeting_prefill
    assert_includes text, "Happy Thanksgiving, brethren! 🍂"
    assert_includes text, "“Enter into his gates with thanksgiving.” (Psalm 100:4)"
    assert_includes text, "#Thanksgiving"
  end

  test "member country comes from their city" do
    houston = member_in(:houston)
    assert_equal "US", houston.profile.city.country_code
  end
end
