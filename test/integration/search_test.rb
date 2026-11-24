# frozen_string_literal: true

require "test_helper"

# The search page, its tabs and filters, the instant dropdown, recent
# searches, the query log and the admin's view of it.
class SearchTest < ActionDispatch::IntegrationTest
  SEEN = { tour_completed_at: Time.current, welcomed_at: Time.current }.freeze

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @me = create_member("seeker_one", **SEEN)
    @writer = create_member("grace_writer", **SEEN)
    @room = Room.create!(name: "Testimony Hall", description: "Stories of grace", room_type: :testimonies, is_public: true)
    @post = Post.create!(user: @writer, room: @room, title: "Amazing grace found me", content: "A testimony of healing and grace.",
                         status: :published, moderation_status: :approved)
  end

  test "an empty search shows the prompt" do
    get search_path
    assert_response :success
    assert_select ".srch-input"
    assert_match "What are you looking for?", response.body
  end

  test "Top mixes breaths, people and rooms; tabs narrow it" do
    sign_in @me
    get search_path(q: "grace")
    assert_response :success
    assert_select ".srch-result-title mark", text: "grace"
    assert_select ".srch-tab.is-active", text: "Top"

    get search_path(q: "grace_writer", tab: "people")
    assert_select ".srch-person-row", text: /@grace_writer/

    get search_path(q: "testimony", tab: "rooms")
    assert_select ".srch-panel-title", text: "Testimony Hall"

    get search_path(q: "grace", tab: "breaths")
    assert_select ".srch-result", 1
    assert_match "1 breath", response.body
  end

  test "filters live in the URL and are applied" do
    other = Room.create!(name: "Questions Room", description: "x", room_type: :questions)
    Post.create!(user: @writer, room: other, title: "Grace question", content: "What is grace?", status: :published, moderation_status: :approved)
    sign_in @me
    get search_path(q: "grace", tab: "breaths", room: other.slug, sort: "newest", date: "week", type: "text")
    assert_select ".srch-result", 1
    assert_select ".srch-result-title", text: /Grace question/
    assert_select "select[name=room] option[selected][value=?]", other.slug
    assert_select "select[name=sort] option[selected][value=newest]"
  end

  test "john 3 16 jumps straight to the verse page" do
    get search_path(q: "john 3 16")
    assert_redirected_to scripture_page_path("john-3-16")
    get search_path(q: "Ps 23")
    assert_redirected_to scripture_page_path("psalm-23")
    get search_path(q: "john 3 16", tab: "bible")
    assert_response :success
    assert_select ".srch-bible-card", text: /John 3:16/
  end

  test "a misspelling suggests the right word and shows close matches" do
    Post.create!(user: @writer, room: @room, title: "Amazing love", content: "Simply amazing.", status: :published, moderation_status: :approved)
    SearchTermsRefreshJob.perform_now
    sign_in @me
    get search_path(q: "amazng")
    assert_response :success
    assert_select ".srch-didyoumean-link", text: "amazing"
    assert_includes response.body, %(href="#{post_path(@post)}")
  end

  test "nothing found shows the empty state" do
    get search_path(q: "zzyzx qwertyuiop")
    assert_select ".srch-empty", text: /Nothing found/
  end

  test "the instant dropdown lists people, rooms and breaths, and recent searches when empty" do
    sign_in @me
    get search_suggest_path(q: "grace")
    assert_response :success
    assert_select "[role=option]", minimum: 3
    assert_select "[role=option][href=?]", user_path("grace_writer")
    assert_select "[role=option][href=?]", post_path(@post)
    assert_select ".srch-dd-all", text: /Search for “grace”/

    get search_suggest_path(q: "john 3:16")
    assert_select "[role=option][href=?]", scripture_page_path("john-3-16")

    get search_path(q: "healing")
    get search_suggest_path(q: "")
    assert_select ".srch-dd-head", text: /Recent searches/
    assert_select "[role=option][data-query=healing]"

    delete search_recent_path
    assert_equal 0, @me.recent_searches.count
    get search_suggest_path(q: "")
    assert_select "[data-search-suggest-empty]"
  end

  test "recent searches are per member and capped" do
    sign_in @me
    10.times { |i| get search_path(q: "word#{i}") }
    assert_equal RecentSearch::KEEP, @me.recent_searches.count
    other = create_member("someone_else", **SEEN)
    assert_equal 0, RecentSearch.for(other).count
  end

  test "searches are logged without personal details" do
    sign_in @me
    assert_difference -> { SearchQuery.count }, 1 do
      get search_path(q: "Grace from:grace_writer call +234 803 555 0101 me@example.com")
    end
    row = SearchQuery.last
    assert_equal @me.id, row.user_id
    assert_equal "grace from:… call [number] [email]", row.query
    assert row.filtered

    assert_no_difference -> { SearchQuery.count } do
      get search_suggest_path(q: "grace")
    end
  end

  test "admins see top and zero-result searches; members can't" do
    SearchQuery.log(text: "healing", tab: "top", results_count: 4)
    SearchQuery.log(text: "healing", tab: "top", results_count: 4)
    SearchQuery.log(text: "unfindable", tab: "top", results_count: 0)
    sign_in @me
    get admin_search_insights_path
    assert_response :redirect

    admin = create_member("insight_admin", role: :admin, **SEEN)
    sign_in admin
    get admin_search_insights_path
    assert_response :success
    assert_select "table.aseo-table", 2
    assert_match "healing", response.body
    assert_match "unfindable", response.body
  end

  test "search is rate limited per member" do
    sign_in @me
    40.times { get search_path(q: "grace") }
    get search_path(q: "grace")
    assert_response :redirect
    assert_match(/a lot|wait/i, flash[:alert].to_s)
  end

  test "the header search box is wired for instant search" do
    sign_in @me
    get feed_path
    assert_select "[data-controller=search-suggest] input[role=combobox][data-search-suggest-target=input]"
    assert_select "#eg-search-listbox[role=listbox]"
  end
end
