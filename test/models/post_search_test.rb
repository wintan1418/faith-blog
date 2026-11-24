# frozen_string_literal: true

require "test_helper"

# The search vectors are kept by database triggers (SiteSearch::Schema);
# SiteSearch::PostSearch reads them.
class PostSearchTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "searcher", email: "searcher@example.com", password: "password123")
    @reader = User.create!(username: "reader_one", email: "reader1@example.com", password: "password123")
    @room = Room.create!(name: "Search Room", description: "x", room_type: :general, is_public: true)
  end

  def make_post(title, body, **attrs)
    Post.create!({ user: @author, room: @room, title: title, content: body, status: :published,
                   moderation_status: :approved }.merge(attrs))
  end

  def search(text, viewer: @reader, **filters)
    SiteSearch::PostSearch.new(SiteSearch::Query.new(text), visibility: SiteSearch::Visibility.new(viewer), filters: filters).call
  end

  def found(text, **opts) = search(text, **opts).posts

  def vector(post) = ActiveRecord::Base.connection.select_value("SELECT searchable::text FROM posts WHERE id = #{post.id}")

  test "the triggers and functions are installed in the test database" do
    assert ActiveRecord::Base.connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname LIKE '%search_refresh'").to_i >= 5
  end

  test "finds posts by words in the body, the title, and by prefix" do
    post = make_post("Morning thoughts", "<div>The <strong>shepherd</strong> leaves the ninety-nine.</div>")
    other = make_post("Evening thoughts", "Rest and quiet.")

    assert_equal [ post ], found("shepherd")
    assert_equal [ post ], found("shepherds") # english stemming
    assert_equal [ post ], found("shep")      # prefix (typing)
    assert_equal [ other ], found("evening")
    assert_empty found("strong"), "HTML tags aren't indexed"
  end

  test "editing the body or title refreshes the vector" do
    post = make_post("Morning thoughts", "Grace upon grace.")
    assert_empty found("covenant")

    post.reload.update!(content: "An everlasting covenant.")
    assert_equal [ post ], found("covenant")
    assert_empty found("grace")

    post.reload.update!(title: "Psalm of ascent")
    assert_equal [ post ], found("ascent")
  end

  test "weights: title A, body B, author C, room D (never the author of an anonymous breath)" do
    post = make_post("Lighthouse", "Harbour stories")
    assert_match(/'lighthous':1A/, vector(post))
    assert_match(/'harbour':\d+B/, vector(post))
    assert_match(/'searcher':\d+C/, vector(post))
    assert_match(/'room':\d+(?![ABC])/, vector(post))

    hidden = make_post("Lantern", "Night watch", anonymous: true)
    assert_no_match(/searcher/, vector(hidden))
  end

  test "renaming the author or the room updates their breaths' vectors" do
    post = make_post("Garden", "Seeds")
    @author.update!(username: "gardener_jo")
    @room.update!(name: "Orchard Hall")
    v = vector(post)
    assert_match(/'jo':\d+C/, v)
    assert_match(/orchard/, v)
    assert_no_match(/searcher/, v)
    assert_equal [ post ], found("orchard")
  end

  test "fancy Unicode letters match plain text, and plain letters match fancy text" do
    fancy = make_post("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)", "Part one")
    plain = make_post("Being a teenager", "𝘐𝘯 𝘵𝘩𝘦 𝘴𝘪𝘭𝘦𝘯𝘤𝘦 𝘰𝘧 𝘵𝘩𝘦 𝘯𝘪𝘨𝘩𝘵")

    assert_includes found("teenager"), fancy
    assert_includes found("𝘁𝗲𝗲𝗻𝗮𝗴𝗲𝗿"), fancy, "typed in fancy letters"
    assert_includes found("𝘁𝗲𝗲𝗻𝗮𝗴𝗲𝗿"), plain, "fancy query finds plain text"
    assert_equal [ plain ], found("silence night")
  end

  test "an exact title (punctuation and styling aside) ranks first" do
    exact = make_post("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)", "Part one", published_at: 2.years.ago)
    make_post("Teenager notes", "Who is a teenager, really? A teenager is a teenager.", likes_count: 50)
    assert_equal exact, found("who is a teenager 1").first
  end

  test "accents don't matter" do
    post = make_post("Café talk", "Noël and the crèche")
    assert_equal [ post ], found("cafe")
    assert_equal [ post ], found("noel creche")
    assert_equal [ post ], found("CAFÉ")
  end

  test "phrases, exclusions and from:" do
    a = make_post("Good shepherd", "The good shepherd lays down his life")
    b = make_post("Shepherd notes", "A shepherd who is good at sums")
    assert_equal [ a ], found('"good shepherd"')
    assert_equal [ b ], found("shepherd -life")
    assert_empty found("-shepherd"), "exclusions alone find nothing"
    other = User.create!(username: "other_writer", email: "other@example.com", password: "password123")
    Post.create!(user: other, title: "Shepherd too", content: "x", status: :published, moderation_status: :approved)
    assert_equal [ a, b ].sort_by(&:id), found("shepherd", author: @author).sort_by(&:id)
  end

  test "filters: room, date, type and sort" do
    other_room = Room.create!(name: "Other Room", description: "x")
    old = make_post("River old", "river", published_at: 2.years.ago, likes_count: 9)
    fresh = make_post("River new", "river", likes_count: 1)
    elsewhere = make_post("River elsewhere", "river", room: other_room)

    assert_equal [ elsewhere ], found("river", room: other_room)
    refute_includes found("river", since: 1.year.ago), old
    newest = found("river", sort: "newest")
    assert_includes [ fresh, elsewhere ], newest.first
    assert_equal old, newest.last
    assert_equal old, found("river", sort: "loved").first
    assert_equal [], found("river", type: "photo")
    assert_equal 3, found("river", type: "text").size
  end

  test "a reply match brings its breath in, marked as reply-only, with a highlighted reply" do
    post = make_post("Sunday lunch", "What do you cook?")
    Comment.create!(post: post, user: @reader, content: "Pepper soup, always")
    result = search("pepper")
    assert_equal [ post ], result.posts
    hit = result.hits.first
    assert hit.reply_only
    assert_includes hit.reply_html, "<mark>Pepper</mark>"
  end

  test "counts are capped, not counted" do
    stub_const(SiteSearch::PostSearch, :CANDIDATES, 3) do
      5.times { |i| make_post("Harvest #{i}", "harvest") }
      result = search("harvest")
      assert result.capped?
      assert_equal 3, result.total
    end
  end

  test "highlights keep the author's styling and escape everything else" do
    make_post("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? <script>", "<div>A teenager &amp; friends</div>")
    hit = search("teenager").hits.first
    assert_equal "𝗪𝗵𝗼 𝗜𝘀 𝗮 <mark>𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿</mark>? &lt;script&gt;", hit.title_html
    assert_includes hit.snippet_html, "A <mark>teenager</mark> &amp; friends"
  end

  test "the stored vectors aren't selected with posts or comments" do
    make_post("Hidden gem", "Treasure")
    refute_includes Post.first.attributes.keys, "searchable"
    refute_includes Post.first.attributes.keys, "search_title"
    refute_includes Comment.column_names - Comment.ignored_columns, "searchable"
  end

  private

  def stub_const(mod, name, value)
    old = mod.const_get(name)
    mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, old)
  end
end
