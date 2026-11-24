# frozen_string_literal: true

require "test_helper"

# Search must never reveal anything the searcher couldn't see by browsing.
# Each test plants a breath with a unique word, then checks every way search
# could leak it: the results page (Top and Breaths tabs), the instant
# dropdown, and the `from:` filter.
class SearchPrivacyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SEEN = { tour_completed_at: Time.current, welcomed_at: Time.current }.freeze

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("lantern_writer", **SEEN)
    @reader = create_member("curious_reader", **SEEN)
    @room = Room.create!(name: "Open Courtyard", description: "Everyone welcome", room_type: :general, is_public: true)
  end

  def breath(word, user: @author, room: @room, **attrs)
    Post.create!({ user: user, room: room, title: "Notes on #{word}", content: "A breath about #{word} and quiet faith.",
                   status: :published, moderation_status: :approved }.merge(attrs))
  end

  # Every surface a word could leak through.
  def surfaces(word)
    [ search_path(q: word), search_path(q: word, tab: "breaths"), search_suggest_path(q: word) ]
  end

  # The breath with this word in its title (results highlight the word, so
  # pages are checked for the breath's link, not its title text).
  def link_for(word)
    post = Post.find_by!(title: "Notes on #{word}")
    %(href="#{post_path(post)}")
  end

  def assert_hidden(word, as: nil, also: [])
    as ? sign_in(as) : sign_out(:user)
    link = link_for(word)
    (surfaces(word) + also).each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, link, "#{path} leaked the breath to #{as&.username || 'a visitor'}"
    end
  end

  def assert_found(word, as: nil)
    as ? sign_in(as) : sign_out(:user)
    get search_path(q: word, tab: "breaths")
    assert_response :success
    assert_includes response.body, link_for(word), "#{as&.username || 'a visitor'} should find the breath"
  end

  test "a public breath is found by members and visitors (control)" do
    breath("marigold")
    assert_found("marigold", as: @reader)
    assert_found("marigold")
  end

  test "drafts, scheduled and archived breaths are never found, not even by staff" do
    breath("draftword", status: :draft)
    breath("laterword", status: :scheduled, scheduled_for: 2.days.from_now)
    breath("archword", status: :archived)
    admin = create_member("search_admin", role: :admin, **SEEN)
    %w[draftword laterword archword].each do |word|
      assert_hidden(word, as: @reader)
      assert_hidden(word, as: admin)
      assert_hidden(word, as: @author)
    end
  end

  test "held and blocked breaths are never found" do
    breath("heldword", moderation_status: :pending_review)
    breath("blockedword", moderation_status: :blocked)
    legacy = breath("legacyword")
    AiModerationReview.create!(reviewable: legacy, user: @author, severity: "high", recommended_action: "require_review", status: :flagged)
    %w[heldword blockedword legacyword].each do |word|
      assert_hidden(word, as: @reader)
      assert_hidden(word)
    end
  end

  test "a private room's breaths are found only by its members and staff" do
    private_room = Room.create!(name: "Elders Table", description: "x", room_type: :general, is_public: false)
    breath("eldersword", room: private_room)
    member = create_member("elder_member", **SEEN)
    RoomMembership.create!(user: member, room: private_room)
    moderator = create_member("search_mod", role: :moderator, **SEEN)

    assert_hidden("eldersword", as: @reader)
    assert_hidden("eldersword")
    assert_found("eldersword", as: member)
    assert_found("eldersword", as: moderator)

    sign_in @reader
    get search_path(q: "elders", tab: "rooms")
    assert_no_match "Elders Table", response.body, "a private room isn't listed to non-members"
    get search_path(q: "eldersword", tab: "breaths", room: private_room.slug)
    assert_not_includes response.body, link_for("eldersword"), "filtering by a private room finds nothing"
    get search_suggest_path(q: "elders")
    assert_no_match "Elders Table", response.body
  end

  test "breaths from people the searcher blocked, or who blocked them, are hidden" do
    blocker = create_member("blocking_member", **SEEN)
    blocked = create_member("blocked_member", **SEEN)
    breath("blockerword", user: blocker)
    breath("blockedauthorword", user: blocked)
    MessageBlock.create!(blocker: blocker, blocked: @reader)
    MessageBlock.create!(blocker: @reader, blocked: blocked)

    assert_hidden("blockerword", as: @reader, also: [ search_path(q: "from:blocking_member blockerword") ])
    assert_hidden("blockedauthorword", as: @reader)
    sign_in @reader
    get search_path(q: "blocking_member", tab: "people")
    assert_no_match "@blocking_member", response.body
    get search_suggest_path(q: "blocked_mem")
    assert_no_match "@blocked_member", response.body
  end

  test "breaths by suspended members are hidden, and so are they" do
    gone = create_member("suspended_member", **SEEN)
    breath("suspendedword", user: gone)
    gone.update_columns(active: false)
    assert_hidden("suspendedword", as: @reader)
    sign_in @reader
    get search_path(q: "suspended_member", tab: "people")
    assert_no_match "@suspended_member", response.body
  end

  test "anonymous breaths are found by their words but never show or match their author" do
    breath("hushedword", anonymous: true)
    sign_in @reader

    get search_path(q: "hushedword", tab: "breaths")
    assert_includes response.body, link_for("hushedword"), "the words are searchable"
    assert_match "Anonymous", response.body
    assert_no_match "lantern_writer", response.body, "the author never shows"
    get search_suggest_path(q: "hushedword")
    assert_no_match "lantern_writer", response.body

    # The author's name doesn't find it ...
    get search_path(q: "lantern_writer", tab: "breaths")
    assert_not_includes response.body, link_for("hushedword")
    # ... and from: can't unmask it, even combined with its words.
    [ search_path(q: "from:lantern_writer hushedword"), search_path(q: "hushedword", from: "lantern_writer", tab: "breaths"),
      search_path(q: "from:@lantern_writer hushedword", tab: "breaths") ].each do |path|
      get path
      assert_not_includes response.body, link_for("hushedword"), "#{path} unmasked an anonymous breath"
    end
  end

  test "from: still finds the author's named breaths" do
    breath("namedword")
    sign_in @reader
    get search_path(q: "from:lantern_writer namedword", tab: "breaths")
    assert_includes response.body, link_for("namedword")
  end

  test "an anonymous breath's vector never holds its author's name, even after a rename" do
    post = breath("vectorword", anonymous: true)
    @author.update!(username: "renamed_writer")
    vector = ActiveRecord::Base.connection.select_value("SELECT searchable::text FROM posts WHERE id = #{post.id}")
    assert_no_match(/lantern|renam|writer/, vector)
  end

  test "signed-out visitors only get public breaths: no anonymous, prayer requests, prayer or struggles rooms" do
    prayers = Room.create!(name: "Prayer Wall Room", description: "x", room_type: :prayers, is_public: true)
    struggles = Room.create!(name: "Struggles Room", description: "x", room_type: :struggles, is_public: true)
    breath("anonvisitorword", anonymous: true)
    breath("prayerrequestword", prayer_status: :prayer_pending)
    breath("prayerroomword", room: prayers)
    breath("strugglesword", room: struggles)

    %w[anonvisitorword prayerrequestword prayerroomword strugglesword].each { |word| assert_hidden(word) }
    # Members browse those rooms, so they find them.
    %w[anonvisitorword prayerrequestword prayerroomword strugglesword].each { |word| assert_found(word, as: @reader) }
  end

  test "replies only count when they're visible: not deleted, held, or from blocked people" do
    host = Post.create!(user: @author, room: @room, title: "Sunday lunch", content: "What do you cook?",
                        status: :published, moderation_status: :approved)
    stranger = create_member("reply_stranger", **SEEN)
    Comment.create!(post: host, user: stranger, content: "Pepper soup with plantain")
    MessageBlock.create!(blocker: @reader, blocked: stranger)
    other = create_member("reply_friend", **SEEN)
    Comment.create!(post: host, user: other, content: "Jollof with fried plantain")
    Comment.create!(post: host, user: other, content: "Moonflower tea", moderation_status: :pending_review)
    Comment.create!(post: host, user: other, content: "Starfruit salad").soft_delete!
    gone = create_member("reply_gone", **SEEN)
    Comment.create!(post: host, user: gone, content: "Tamarind juice")
    gone.update_columns(active: false)

    sign_in @reader
    get search_path(q: "jollof", tab: "breaths")
    assert_includes response.body, %(href="#{post_path(host)}")
    assert_match "Matched in a reply", response.body
    %w[pepper moonflower starfruit tamarind].each do |word|
      get search_path(q: word, tab: "breaths")
      assert_not_includes response.body, %(href="#{post_path(host)}"), "a hidden reply (#{word}) surfaced its breath"
    end
  end

  test "series follow the series page's rules" do
    open_series = Series.create!(user: @author, title: "Lanterns in the dark")
    breath("lanternpart").update_columns(series_id: open_series.id, series_position: 1)
    private_room = Room.create!(name: "Inner Room", description: "x", is_public: false)
    hidden_series = Series.create!(user: @author, title: "Lanterns behind doors")
    breath("doorpart", room: private_room).update_columns(series_id: hidden_series.id, series_position: 1)

    sign_in @reader
    get search_path(q: "lanterns", tab: "series")
    assert_includes response.body, series_path(open_series)
    assert_not_includes response.body, series_path(hidden_series), "a series with only private-room parts stays hidden"

    MessageBlock.create!(blocker: @author, blocked: @reader)
    get search_path(q: "lanterns", tab: "series")
    assert_not_includes response.body, series_path(open_series), "a blocked author's series is hidden"

    @author.profile&.update_columns(public_profile: false)
    sign_out :user
    get search_path(q: "lanterns", tab: "series")
    assert_not_includes response.body, series_path(open_series) if @author.profile
  end

  test "member search stays members-only" do
    get search_path(q: "lantern", tab: "people")
    assert_redirected_to new_user_session_path
    get search_suggest_path(q: "lantern")
    assert_no_match "@lantern_writer", response.body
  end
end
