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
    assert_includes response.body, "<sitemapindex"
    assert_includes response.body, pages_sitemap_url
    assert_includes response.body, scripture_sitemap_url(page: 1)

    get pages_sitemap_url
    assert_response :success
    body = response.body
    assert_includes body, post_url(open_post)
    assert_includes body, room_url(@room)
    assert_not_includes body, post_url(private_post)
    assert_not_includes body, post_url(draft)
    assert_not_includes body, room_url(@hidden)
  end

  test "the scripture sitemap lists every chapter, the popular verses and quoted verses" do
    Post.create!(title: "Quoting", content: "Nahum 2:3 struck me.", room: @room, user: @ada, status: "published")
    Post.create!(title: "Private quote", content: "Obadiah 1:4 struck me.", room: @hidden, user: @ada, status: "published")
    ScriptureInsight.create!(reference: "Psalm 101:3", slug: "psalm-101-3", explanation: "x", context: "y",
                             generated_at: Time.utc(2026, 11, 20))

    get scripture_sitemap_url(page: 1)

    assert_response :success
    doc = Nokogiri::XML(response.body)
    locs = doc.xpath("//xmlns:loc").map(&:text)
    assert_includes locs, scripture_index_url
    assert_includes locs, scripture_page_url(slug: "john-3-16")
    assert_includes locs, scripture_page_url(slug: "1-john-1-9")
    assert_includes locs, scripture_page_url(slug: "psalm-23")
    assert_includes locs, scripture_page_url(slug: "revelation-22")
    assert_includes locs, scripture_page_url(slug: "nahum-2-3")
    assert_not_includes locs, scripture_page_url(slug: "obadiah-1-4")
    assert_operator locs.size, :>, 1_189 + 500
    assert_equal locs.uniq, locs
    psalm = doc.xpath("//xmlns:url[xmlns:loc='#{scripture_page_url(slug: 'psalm-101-3')}']/xmlns:lastmod").text
    assert_equal "2026-11-20", psalm

    get "/sitemaps/scripture-2.xml"
    assert_response :not_found
  end

  test "scripture slugs round-trip to their pages" do
    assert_equal "1-john-1-9", SitemapsController.scripture_slug("1 John 1:9")
    get scripture_page_path(slug: SitemapsController.scripture_slug("Proverbs 3:5-6"))
    assert_response :success
  end

  test "pages carry a canonical link, a JPEG preview and structured data" do
    get root_path
    assert_select "title", text: /Sane, kind conversations about work, life and faith/
    assert_select "link[rel=canonical][href=?]", root_url
    assert_select "meta[property='og:image'][content$='/og/mint.jpg']"
    assert_select "script[type='application/ld+json']", text: /"Organization"/
    assert File.exist?(Rails.root.join("public/og/mint.jpg"))
  end

  test "a public breath with a picture shares a full image address" do
    post = Post.create!(title: "With a picture", content: "x", room: @room, user: @ada, status: "published",
                        moderation_status: :approved, published_at: Time.current)
    post.images.attach(io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")),
                       filename: "p.png", content_type: "image/png")
    get post_path(post)
    image = css_select("meta[property='og:image']").first["content"]
    assert_match %r{\Ahttps?://}, image
    assert_equal image, css_select("meta[name='twitter:image']").first["content"]
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
