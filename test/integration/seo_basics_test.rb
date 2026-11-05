# frozen_string_literal: true

require "test_helper"

# What search engines and link previews see.
class SeoBasicsTest < ActionDispatch::IntegrationTest
  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_seo", email: "ada-seo@example.com", password: @pass, password_confirmation: @pass)
    @room = Room.create!(name: "SEO Room", description: "x", is_public: true)
    @hidden = Room.create!(name: "Hidden Room", description: "x", is_public: false)
  end

  test "the sitemap lists public pages and leaves private ones out" do
    open_post = Post.create!(title: "Grace for today", content: "Grace.", room: @room, user: @ada, status: "published")
    private_post = Post.create!(title: "Members only", content: "Shh.", room: @hidden, user: @ada, status: "published")
    draft = Post.create!(title: "Not yet", content: "Draft.", room: @room, user: @ada, status: "draft")

    get "/sitemap.xml"

    assert_response :success
    body = response.body
    assert_includes body, post_url(open_post)
    assert_includes body, room_url(@room)
    assert_includes body, scripture_page_url(slug: "john-3-16")
    assert_includes body, scripture_page_url(slug: "1-john-1-9")
    assert_not_includes body, post_url(private_post)
    assert_not_includes body, post_url(draft)
    assert_not_includes body, room_url(@hidden)
  end

  test "scripture slugs round-trip to their pages" do
    assert_equal "1-john-1-9", SitemapsController.scripture_slug("1 John 1:9")
    get scripture_page_path(slug: SitemapsController.scripture_slug("Proverbs 3:5-6"))
    assert_response :success
  end

  test "pages carry a canonical link, a JPEG preview and structured data" do
    get root_path
    assert_select "title", text: /Christian community for prayer, scripture and fellowship/
    assert_select "link[rel=canonical][href=?]", root_url
    assert_select "meta[property='og:image'][content$='/og/mint.jpg']"
    assert_select "script[type='application/ld+json']", text: /"Organization"/
    assert File.exist?(Rails.root.join("public/og/mint.jpg"))
  end

  test "a breath's structured data can't break out of its script tag" do
    post = Post.create!(title: "Hello </script><script>alert(1)</script>", content: "x", room: @room, user: @ada, status: "published")
    get post_path(post)
    assert_select "link[rel=canonical][href=?]", post_url(post)
    data = css_select("script[type='application/ld+json']").map(&:inner_html).find { |s| s.include?("DiscussionForumPosting") }
    assert data, "posts describe themselves"
    assert_not_includes data, "</script>"
    assert_equal "DiscussionForumPosting", JSON.parse(data)["@type"]
  end

  test "robots.txt points to the sitemap and keeps private areas out" do
    robots = Rails.root.join("public/robots.txt").read
    assert_includes robots, "Sitemap: https://brethreign.com/sitemap.xml"
    assert_includes robots, "Disallow: /inbox"
  end
end
