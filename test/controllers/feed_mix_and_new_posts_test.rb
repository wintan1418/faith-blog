# frozen_string_literal: true

require "test_helper"

# The founder posted 50 breaths in an hour and the Recent feed became one long
# run of his posts. The feed now spreads one author out, pages stay stable,
# and a "New posts" pill tells members what arrived since they last looked.
class FeedMixAndNewPostsTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    pw = "Pw-#{SecureRandom.hex(8)}"
    @reader = User.create!(username: "mixreader", email: "mixreader@example.com", password: pw)
    @busy   = User.create!(username: "busyauthor", email: "busy@example.com", password: pw)
    @others = (1..4).map { |i| User.create!(username: "member#{i}", email: "member#{i}@example.com", password: pw) }
    @room = Room.create!(name: "Mix Room", description: "x", room_type: :general, is_public: true)
  end

  def breath(user, at, title, **attrs)
    Post.create!(user: user, room: @room, title: title, content: "Body of #{title}", status: :published,
                 moderation_status: :approved, published_at: at, **attrs)
  end

  def feed_titles(body = response.body)
    Nokogiri::HTML(body).css(".fc-breath-title").map { |e| e.text.strip }
  end

  def author_of(title) = title.split(" ").first

  test "Recent spreads out a burst from one author and pages carry on with no repeats or gaps" do
    30.times { |i| breath(@busy, (i + 1).minutes.ago, "busy #{i}") }
    12.times { |i| breath(@others[i % 4], (2 + i * 5).hours.ago, "member#{i % 4 + 1} #{i}") }
    sign_in @reader

    get feed_path
    page_one = feed_titles
    assert_equal 20, page_one.size
    runs = page_one.map { |t| author_of(t) }.chunk_while { |a, b| a == b }.map(&:size)
    assert_operator runs.max, :<=, 2, "no more than two in a row from one author: #{page_one.inspect}"

    next_url = Nokogiri::HTML(response.body).at_css("#feed_more")["data-infinite-scroll-url-value"]
    # Someone posts while they're reading: page two still continues the same list.
    breath(@others.first, Time.current, "member1 late")

    get next_url, as: :turbo_stream
    page_two = feed_titles
    get next_url.sub("page=2", "page=3"), as: :turbo_stream
    page_three = feed_titles

    all = page_one + page_two + page_three
    assert_equal all.uniq, all, "no card shows twice"
    assert_equal 42, all.size, "every breath appears once"
    assert_not_includes all, "member1 late", "new arrivals wait for the pill"
  end

  test "pinned posts still lead the feed" do
    5.times { |i| breath(@busy, (i + 1).minutes.ago, "busy #{i}") }
    breath(@others.first, 3.days.ago, "member1 pinned", featured: true)
    sign_in @reader

    get feed_path
    assert_equal "member1 pinned", feed_titles.first
  end

  test "Recent stays cheap: a fixed number of queries however many posts there are" do
    sign_in @reader
    count_queries = lambda do
      n = 0
      cb = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { get feed_path }
      n
    end
    20.times { |i| breath(@others[i % 4], (i + 1).minutes.ago, "member #{i}") }
    small = count_queries.call
    40.times { |i| breath(@busy, (i + 1).seconds.ago, "busy #{i}") }
    large = count_queries.call
    assert_operator large, :<=, small + 3, "queries: #{small} → #{large}"
  end

  test "viewing the top of Recent records feed_seen_at, at most once a minute" do
    sign_in @reader
    freeze_time do
      get feed_path
      first = @reader.reload.feed_seen_at
      assert_in_delta Time.current, first, 1

      travel 30.seconds
      get feed_path
      assert_equal first, @reader.reload.feed_seen_at, "throttled"

      travel 31.seconds
      get feed_path
      assert_operator @reader.reload.feed_seen_at, :>, first
    end
  end

  test "posts since the last visit get a New dot and come first" do
    breath(@others.first, 3.hours.ago, "member1 old")
    @reader.update_column(:feed_seen_at, 2.hours.ago)
    breath(@others.second, 1.hour.ago, "member2 new")
    sign_in @reader

    get feed_path
    doc = Nokogiri::HTML(response.body)
    cards = doc.css("article, .fc-breath").select { |c| c.at_css(".fc-breath-title") }
    fresh = cards.find { |c| c.at_css(".fc-breath-title").text.include?("member2 new") }
    old   = cards.find { |c| c.at_css(".fc-breath-title").text.include?("member1 old") }
    assert fresh.at_css(".fc-new-dot"), "unseen post has the New dot"
    assert_nil old.at_css(".fc-new-dot")
  end

  test "new_posts counts unseen posts and shows up to three author faces" do
    since = 10.minutes.ago
    breath(@others[0], 5.minutes.ago, "a")
    breath(@others[1], 4.minutes.ago, "b")
    breath(@others[2], 3.minutes.ago, "c")
    breath(@others[3], 2.minutes.ago, "d")
    breath(@others[0], 20.minutes.ago, "before since")
    breath(@reader, 1.minute.ago, "my own")
    sign_in @reader

    get feed_new_posts_path(since: (since.to_r * 1_000_000).to_i)
    assert_response :success
    assert_select "[data-new-posts-count='4']"
    assert_select ".fc-pill-face", 3
    assert_select ".fc-pill-label", "4 new posts"
  end

  test "new_posts leaves out blocked people, held posts, and never shows an anonymous author" do
    since = 10.minutes.ago
    MessageBlock.create!(blocker: @reader, blocked: @others[0])
    breath(@others[0], 5.minutes.ago, "blocked")
    breath(@others[1], 4.minutes.ago, "held", moderation_status: :pending_review)
    breath(@others[2], 3.minutes.ago, "anon", anonymous: true)
    sign_in @reader

    get feed_new_posts_path(since: (since.to_r * 1_000_000).to_i)
    assert_select "[data-new-posts-count='1']"
    assert_select ".fc-pill-face", 0
    assert_no_match "member3", response.body
  end

  test "new_posts: nothing new since the page was built hides the pill" do
    breath(@others[0], 5.minutes.ago, "a")
    sign_in @reader
    get feed_new_posts_path(since: (Time.current.to_r * 1_000_000).to_i)
    assert_select "[data-new-posts-count='0']"
    assert_select ".fc-pill-label", 0
  end

  test "a post seen elsewhere (feed_seen_at later than the page) doesn't count" do
    breath(@others[0], 5.minutes.ago, "a")
    @reader.update_column(:feed_seen_at, 1.minute.ago)
    sign_in @reader
    get feed_new_posts_path(since: (1.hour.ago.to_r * 1_000_000).to_i)
    assert_select "[data-new-posts-count='0']"
  end

  test "a scheduled post going live sends the live marker" do
    post = Post.create!(user: @others[0], room: @room, content: "Scheduled word", status: :scheduled,
                        scheduled_for: 1.minute.ago)
    assert_turbo_stream_broadcasts("feed:public", count: 1) { ScheduledPostPublisherJob.new.perform }
    assert post.reload.published?
  end

  test "a newly published post sends the live marker; a held one doesn't" do
    assert_no_turbo_stream_broadcasts("feed:public") do
      breath(@others[1], Time.current, "held", moderation_status: :pending_review)
    end
    assert_turbo_stream_broadcasts("feed:public", count: 1) { breath(@others[0], Time.current, "live") }
  end

  test "the pill's check isn't counted as a page view" do
    sign_in @reader
    assert_no_difference(-> { Ahoy::Event.count }) { get feed_new_posts_path(since: 1) }
  end

  test "a draft published by editing sends the live marker" do
    post = Post.create!(user: @others[0], room: @room, content: "Draft word", status: :draft)
    assert_turbo_stream_broadcasts("feed:public", count: 1) { post.update!(status: :published) }
  end
end
