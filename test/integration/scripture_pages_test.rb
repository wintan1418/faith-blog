# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Scripture pages for the whole Bible: canonical URLs, the text from the
# database, stored insights, structured data and the breaths that quote a
# verse (public, named, non-prayer ones only).
class ScripturePagesTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("verse_author")
    @room = Room.create!(name: "Verse Room", description: "x", is_public: true)
    seed_verses
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def seed_verses
    rows = []
    { "kjv" => "KJV", "web" => "WEB", "bsb" => "BSB" }.each do |code, label|
      (1..8).each do |v|
        rows << { translation: code, book: 19, chapter: 101, verse: v,
                  text: v == 3 ? "#{label}: I will set no wicked thing before mine eyes: I hate the work of them that turn aside." : "#{label} Psalm 101 verse #{v}." }
      end
      (1..6).each { |v| rows << { translation: code, book: 19, chapter: 23, verse: v, text: "#{label} Psalm 23 verse #{v}." } }
    end
    rows << { translation: "kjv", book: 18, chapter: 31, verse: 1, text: "I made a covenant with mine eyes." }
    ScriptureVerse.insert_all(rows)
    ScriptureCrossReference.create!(book: 19, chapter: 101, verse: 3, to_book: 18, to_chapter: 31, to_verse: 1, votes: 40)
  end

  def publish(title, content, **attrs)
    Post.create!({ user: @author, room: @room, title: title, content: content, status: :published,
                   moderation_status: :approved }.merge(attrs))
  end

  test "a verse page: title, canonical, translations, cross-references and context" do
    get scripture_page_path("psalm-101-3")

    assert_response :success
    assert_select "title", text: "Psalm 101:3 — “KJV: I will set no wicked thing before mine eyes” (KJV): Meaning and Context"
    assert_select "h1 .sx-ref", text: "Psalm 101:3"
    assert_select "link[rel=canonical][href=?]", scripture_page_url("psalm-101-3")
    assert_select "meta[property='og:url'][content=?]", scripture_page_url("psalm-101-3")
    assert_select "meta[property='og:image'][content^='http']"
    assert_select "meta[name=description][content*='I will set no wicked thing']"
    assert_select "figure.sx-alt figcaption", text: /World English Bible/
    assert_select "figure.sx-alt figcaption", text: /Berean Standard Bible/
    assert_select "ul.sx-xrefs a[href=?]", scripture_page_path("job-31-1"), text: "Job 31:1"
    assert_select "ul.sx-xrefs p", text: /covenant with mine eyes/
    assert_select ".sx-context p.is-current", count: 1
    assert_select "a[rel=prev][href=?]", scripture_page_path("psalm-101-2")
    assert_select "a[rel=next][href=?]", scripture_page_path("psalm-101-4")
    assert_select "h2", text: /What does Psalm 101:3 mean/, count: 0
  end

  test "renders a stored insight, and FAQ data only when there is one" do
    get scripture_page_path("psalm-101-3")
    assert_no_match "FAQPage", response.body

    ScriptureInsight.create!(reference: "Psalm 101:3", slug: "psalm-101-3", summary: "A promise to guard the eyes.",
                             explanation: "It means guarding what you look at.\n\nSecond paragraph.",
                             context: "Traditionally attributed to David.", questions: [ "What do you watch?", "Why?", "How?" ],
                             model: "test", generated_at: Time.current)
    get scripture_page_path("psalm-101-3")

    assert_select "h2", text: "What does Psalm 101:3 mean?"
    assert_select ".sx-prose p", text: "Second paragraph."
    assert_select ".sx-questions li", count: 3
    assert_select "meta[name=description][content=?]", "A promise to guard the eyes."
    data = structured_data
    faq = data.find { |node| node["@type"] == "FAQPage" }
    assert faq
    assert_equal "What does Psalm 101:3 mean?", faq["mainEntity"].first["name"]
    assert_includes faq["mainEntity"].first.dig("acceptedAnswer", "text"), "guarding what you look at"
  end

  test "structured data is valid JSON with breadcrumbs, and the Organization stays" do
    get scripture_page_path("psalm-101-3")

    scripts = css_select("script[type='application/ld+json']").map { |s| JSON.parse(s.inner_html) }
    assert(scripts.any? { |s| Array(s["@graph"]).any? { |n| n["@type"] == "Organization" } })
    crumbs = structured_data.find { |node| node["@type"] == "BreadcrumbList" }
    assert_equal [ "Bible", "Psalms", "Psalm 101", "Psalm 101:3" ], crumbs["itemListElement"].map { |i| i["name"] }
    assert_equal scripture_page_url("psalm-101-3"), crumbs["itemListElement"].last["item"]
  end

  test "a chapter page shows the whole chapter in every translation with verse links" do
    get scripture_page_path("psalm-23")

    assert_response :success
    assert_select "h1 .sx-ref", text: "Psalm 23"
    assert_select ".sx-tab", count: 3
    assert_select ".sx-tab-panel--kjv a.sx-vnum", count: 6
    assert_select ".sx-tab-panel--kjv a.sx-vnum[href=?]", scripture_page_path("psalm-23-4")
    assert_select "a[rel=prev][href=?]", scripture_page_path("psalm-22")
  end

  test "other spellings 301 to the canonical page; books go to the index; garbage 404s" do
    {
      "psalms-101-3" => "psalm-101-3", "Psalm-23" => "psalm-23", "genesis-1-11-to-12" => "genesis-1-11-12",
      "ps-23" => "psalm-23", "ephesians-chapter-1-verse-3" => "ephesians-1-3", "john-3-16-16" => "john-3-16"
    }.each do |from, to|
      get "/scripture/#{from}"
      assert_redirected_to scripture_page_path(to), from
      assert_equal 301, response.status
    end

    get "/scripture/genesis"
    assert_redirected_to scripture_index_path(anchor: "genesis")

    get "/scripture/not-a-verse"
    assert_response :not_found
  end

  test "the queries we rank for all resolve to pages" do
    ScriptureLookup.stub(:lookup, nil) do
      %w[psalm-101-3 genesis-1-11-12 2-timothy-3-2-5 isaiah-14-13-14 ephesians-1-3].each do |slug|
        get scripture_page_path(slug)
        assert_response :success, slug
      end
    end
  end

  test "without imported text it falls back to the live lookup and still renders" do
    payload = { reference: "John 3:16", text: "For God so loved the world.",
                verses: [ { chapter: 3, verse: 16, text: "For God so loved the world." } ], translation: "KJV" }
    ScriptureLookup.stub(:lookup, payload) { get scripture_page_path("john-3-16") }
    assert_response :success
    assert_select "blockquote.sx-verse", text: /For God so loved/

    ScriptureLookup.stub(:lookup, nil) { get scripture_page_path("john-3-17") }
    assert_response :success
    assert_select ".sx-missing"
  end

  test "discussions show public, named breaths and never prayers, private rooms or anonymous ones" do
    shown = publish("Guarding my eyes", "Psalm 101:3 has been on my mind.")
    publish("Chapter thought", "All of Psalm 101 tonight.")
    publish("Other verse", "Psalm 101:5 is hard.")
    publish("Pray for me", "Psalm 101:3 please pray", prayer_status: :prayer_pending)
    publish("Secret", "Psalm 101:3 in here", room: Room.create!(name: "Hidden", description: "x", is_public: false))
    publish("Prayer room", "Psalm 101:3 again", room: Room.create!(name: "Prayers", description: "x", room_type: :prayers))
    publish("Nameless", "Psalm 101:3 from nobody", anonymous: true)
    publish("Draft", "Psalm 101:3 draft", status: :draft)
    publish("Held", "Psalm 101:3 held", moderation_status: :pending_review)

    get scripture_page_path("psalm-101-3")

    assert_select ".sx-talk li", count: 1
    assert_select ".sx-talk a[href=?]", post_path(shown), text: /Guarding my eyes/
    %w[Pray\ for\ me Secret Prayer\ room Nameless Draft Held Other\ verse Chapter\ thought].each do |title|
      assert_no_match title, css_select(".sx-talk").to_s
    end
    assert_select ".sx-cta a[href=?]", new_user_registration_path

    get scripture_page_path("psalm-101")
    assert_select ".sx-talk li", count: 3 # the verse, the chapter and verse 5 posts
  end

  test "editing a breath re-indexes its citations" do
    post = publish("Edit me", "Psalm 101:3")
    assert_equal [ [ 19, 101, 3 ] ], post.scripture_citations.pluck(:book, :chapter, :verse_start)
    post.update!(content: "Now Romans 8:28 instead")
    assert_equal [ [ 45, 8, 28 ] ], post.reload.scripture_citations.pluck(:book, :chapter, :verse_start)
  end

  test "the index lists every book and chapter" do
    get scripture_index_path

    assert_response :success
    assert_select "details.sx-book", count: 66
    assert_select ".sx-chapter-grid a", count: 1_189
    assert_select "details#psalm .sx-chapter-grid a[href=?]", scripture_page_path("psalm-150")
    assert_select "link[rel=canonical][href=?]", scripture_index_url
  end

  test "references inside a breath link to their scripture pages" do
    post = publish("Linked", "Today I read Psalm 101:3 and 1 Cor. 13:4-7.")
    get post_path(post)

    assert_select ".post-body a.scripture-ref[href=?]", scripture_page_path("psalm-101-3"), text: "Psalm 101:3"
    assert_select ".post-body a.scripture-ref[href=?]", scripture_page_path("1-corinthians-13-4-7"), text: "1 Cor. 13:4-7"
  end

  private

  def structured_data
    css_select("script[type='application/ld+json']").flat_map do |script|
      json = JSON.parse(script.inner_html)
      json["@graph"] || [ json ]
    end
  end
end
