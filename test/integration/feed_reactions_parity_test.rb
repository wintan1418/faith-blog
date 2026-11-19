# frozen_string_literal: true

require "test_helper"

# Feed cards used to preload every Like (and its user) for every post. They
# now read per-emoji tallies and the viewer's own like; the cards must look
# exactly the same.
class FeedReactionsParityTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @viewer = make_user("parity_viewer")
    @author = make_user("parity_author")
    @room = Room.create!(name: "Parity Room", description: "x", room_type: :general, is_public: true)
    @post = make_post("Many reactions here")
    @quiet = make_post("No reactions here")
  end

  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: "password123", password_confirmation: "password123")
  end

  def make_post(title)
    Post.create!(user: @author, room: @room, title: title, content: "Grace and peace.", status: :published,
                 moderation_status: :approved)
  end

  def react(post, user, emoji, type: :love)
    Like.create!(user: user, likeable: post, reaction_type: type, reaction_emoji: emoji)
  end

  # What the old view code computed from the loaded likes.
  def old_summary(post)
    reacted = post.likes.to_a.reject { |l| l.reaction_emoji.to_s.empty? }
    groups = reacted.group_by(&:reaction_emoji).sort_by { |_, g| -g.size }
    [ groups.first(3).map(&:first), reacted.size ]
  end

  test "summary shows the same top emojis and total, and the viewer's own reaction" do
    3.times { |i| react(@post, make_user("pray#{i}"), "🙏", type: :amen) }
    2.times { |i| react(@post, make_user("love#{i}"), "❤️") }
    react(@post, make_user("fire0"), "🔥")
    react(@post, make_user("star0"), "⭐")
    react(@post, make_user("legacy0"), nil) # no emoji: never counted on the card
    react(@post, @viewer, "❤️")

    sign_in @viewer
    get feed_path
    assert_response :success

    top, total = old_summary(@post)
    assert_equal 8, total
    assert_equal [ "🙏", "❤️" ], top.first(2)

    assert_select "##{ActionView::RecordIdentifier.dom_id(@post, :reaction_summary)}" do
      assert_select ".fc-breath-stats-count", text: "8"
      assert_select ".eg-react-dot", count: 3
      assert_select ".eg-react-dot.is-pray", count: 1
      assert_select ".eg-react-dot.is-love", count: 1
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(@post, :reactions)} .fc-react-btn.is-mine[data-reaction='❤️']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@quiet, :reaction_summary)}.is-empty"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@quiet, :reactions)} .fc-react-btn.is-mine", count: 0
  end

  test "a page of cards doesn't load Like rows per post" do
    posts = Array.new(6) { |i| make_post("Card number #{i}") }
    posts.each_with_index { |p, i| react(p, make_user("fan#{i}"), "🙏", type: :amen) }
    react(posts.first, @viewer, "🙏", type: :amen)

    sign_in @viewer
    like_queries = []
    counter = ->(*, payload) { like_queries << payload[:sql] if payload[:sql].include?('FROM "likes"') }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get feed_path }

    assert_response :success
    card_queries = like_queries.grep(/"likes"."likeable_type" = \$\d|"likes"."likeable_type" = 'Post'/)
                               .grep(/"likes"."likeable_id" IN|"likes"."likeable_id" = ANY|COUNT\(\*\) AS tally/)
    assert_operator card_queries.size, :<=, 2, "expected one tally query and one viewer-like query, got:\n#{card_queries.join("\n")}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(posts.first, :reactions)} .fc-react-btn.is-mine"
  end

  test "the breath page's reaction bar keeps its counts, tooltips and own-reaction pill" do
    names = Array.new(14) { |i| make_user("bar#{i}") }
    names.each { |u| react(@post, u, "🙏", type: :amen) }
    react(@post, @viewer, "❤️")

    sign_in @viewer
    get post_path(@post)
    assert_response :success

    assert_select "##{ActionView::RecordIdentifier.dom_id(@post, :reactions_bar)}" do
      assert_select ".fc-reaction-pill", count: 2
      assert_select ".fc-reaction-pill.is-mine .fc-reaction-emoji", text: "❤️"
      assert_select ".fc-reaction-pill .fc-reaction-count", text: "14"
      assert_select ".fc-reaction-tip", text: /bar0, bar1, .*bar11 and 2 others/
      assert_select ".fc-reaction-viewers", text: "15 reactions"
    end
  end

  test "has_liked? uses the preloaded viewer like" do
    react(@post, @viewer, "🙏", type: :praying)
    Current.user = @viewer
    post = Post.for_cards.find(@post.id)
    assert post.association(:viewer_like).loaded?
    assert_no_queries_matching(/FROM "likes"/) { assert @viewer.has_liked?(post) }
    refute @author.has_liked?(post)
  ensure
    Current.reset
  end

  private

  def assert_no_queries_matching(pattern, &block)
    hits = []
    counter = ->(*, payload) { hits << payload[:sql] if payload[:sql] =~ pattern }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    assert_empty hits
  end
end
