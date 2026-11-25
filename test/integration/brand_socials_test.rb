# frozen_string_literal: true

require "test_helper"

# "Follow Brethreign": one list of accounts (config/socials.yml), shown around the site.
class BrandSocialsTest < ActionDispatch::IntegrationTest
  URLS = {
    "x" => "https://x.com/_Brethreign_",
    "instagram" => "https://www.instagram.com/breth_reign/",
    "linkedin" => "https://www.linkedin.com/company/brethreign/",
    "substack" => "https://breathreigns.substack.com"
  }.freeze

  setup { ENV["AI_MODERATION_STUB"] = "1" }
  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "the accounts come from config/socials.yml" do
    assert_equal URLS.values, BrandSocials.same_as
    assert_equal "social@brethreign.com", BrandSocials.email
    assert_equal "@_Brethreign_", BrandSocials.find(:x).handle
  end

  test "the static 404 page links every account (it can't read the config)" do
    html = Rails.root.join("public/404.html").read
    BrandSocials.all.each { |account| assert_includes html, %(href="#{account.url}"), account.key }
  end

  test "the welcome page: a follow row opening in a new tab, and sameAs for search engines" do
    get root_path
    assert_response :success
    URLS.each_value do |url|
      assert_select ".welcome-footer a.sx-link[href=?][target=_blank][rel~=noopener]", url
    end
    assert_select ".welcome-footer a.sx-link[href=?]", "mailto:social@brethreign.com"

    ld = css_select("script[type='application/ld+json']").map { |s| JSON.parse(s.text) }
    org = ld.flat_map { |d| Array(d["@graph"]) }.find { |n| n["@type"] == "Organization" }
    assert_equal URLS.values, org["sameAs"] & URLS.values
    assert_equal "social@brethreign.com", org.dig("contactPoint", "email")
  end

  test "the feed's left rail has the follow row; the follow card shows from the third visit, once" do
    member = create_member("sx_member", created_at: 3.days.ago)
    sign_in member
    get feed_path
    assert_select ".sx-rail-card a.sx-link[href=?]", URLS["x"]
    assert_select ".sx-feed-card", 0

    3.times { Ahoy::Visit.create!(visit_token: SecureRandom.hex, visitor_token: SecureRandom.hex, user_id: member.id, started_at: 1.day.ago) }
    Post.create!(user: create_member("sx_writer"), title: "Hello", content: "Hello brethren, a good morning to you all.",
                 status: :published, moderation_status: :approved)
    get feed_path
    assert_select ".sx-feed-card[data-socials-card-key-value=?]", FeedController::SOCIALS_CARD_KEY do
      assert_select "a.sx-link", 4
    end

    member.dismiss_card!(FeedController::SOCIALS_CARD_KEY)
    get feed_path
    assert_select ".sx-feed-card", 0
  end

  test "the official page's About tab shows Brethreign's accounts; other pages show their own" do
    owner = create_member("sx_owner", created_at: 30.days.ago)
    official = Page.create!(name: "Brethreign", handle: "brethreign", category: "community", created_by: owner, staff_override: true)
    get about_org_page_path(official.handle)
    assert_select ".pg-panel a.sx-link[href=?]", URLS["instagram"]

    church = Page.create!(name: "Grace Chapel", handle: "gracechapel", category: "church", created_by: owner,
                          socials: { "instagram" => "instagram.com/gracechapel", "myspace" => "https://myspace.com/x", "x" => "" })
    assert_equal({ "instagram" => "https://instagram.com/gracechapel" }, church.socials)
    get about_org_page_path(church.handle)
    assert_select ".pg-panel a.sx-link[href=?]", "https://instagram.com/gracechapel"
    assert_select ".pg-panel a.sx-link[href=?]", URLS["x"], 0
  end

  test "What's new can carry a Follow Brethreign button" do
    member = create_member("sx_wn", created_at: 1.week.ago)
    Announcement.releases.delete_all
    Announcement.create!(kind: :release, title: "New", body: "📣 Follow Brethreign — News, verses and updates [[socials]]")
    sign_in member
    get feed_path
    assert_select "dialog.wn details.wn-socials summary", text: "Follow Brethreign"
    assert_select "dialog.wn .wn-socials-sheet a.sx-link", 4
  end

  test "emails end with the follow links" do
    html = ApplicationController.renderer.render(inline: "<p>Hi</p>", layout: "mailer")
    URLS.each_value { |url| assert_includes html, url }
  end
end
