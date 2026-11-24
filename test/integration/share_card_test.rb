# frozen_string_literal: true

require "test_helper"

# The data behind "Snapshot for status" and "Share as thread" (ShareCard):
# who may be shown, what replies may travel outside, and the ref every link
# and QR code carries.
class ShareCardTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("card_author", accent_color: "violet", verified_at: Time.current)
    @sharer = create_member("card_sharer")
    @post = Post.create!(user: @author, title: "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)", content: "Listen before you lecture. 🙏",
                         status: :published, moderation_status: :approved, published_at: 1.hour.ago)
  end

  def card(post = @post, **params)
    get post_share_card_path(post, **params)
    assert_response :success
    response.parsed_body
  end

  def reply(user, text, post: @post, likes: 0, **attrs)
    Comment.create!(user: user, post: post, content: text, **attrs).tap { |c| c.update_columns(likes_count: likes) }
  end

  test "a public breath's card: author, words, counts, and a link and QR carrying the sharer" do
    @post.update_columns(likes_count: 12, comments_count: 3, reshares_count: 2)
    sign_in @sharer
    data = card

    assert_equal "card_author", data["author"]["username"]
    assert data["author"]["verified"]
    assert_equal "#c084fc", data["accent"]
    assert_equal "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)", data["title"]
    seeds = SeedEvent.where(post_id: @post.id, user_id: @author.id).sum(:points)
    assert_operator seeds, :>, 0
    assert_equal({ "likes" => 12, "comments" => 3, "reshares" => 2, "seeds" => seeds }, data["counts"])
    assert_equal short_post_url(code: @post.id.to_s(36), ref: "card_sharer"), data["link"]
    assert_equal "example.com/b/#{@post.id.to_s(36)}/card_sharer", data["link_label"]
    assert_includes data["share_text"], data["link"]
    assert data["qr"].is_a?(Array) && data["qr"].first.match?(/\A[01]+\z/)
    assert_nil data["series"]
  end

  test "guests can make a card too, without a ref" do
    data = card
    assert_equal short_post_url(code: @post.id.to_s(36)), data["link"]
  end

  test "an anonymous breath never shows who wrote it, even to its author" do
    secret = Post.create!(user: @author, title: "Please pray", content: "Hard week.", anonymous: true,
                          status: :published, moderation_status: :approved, published_at: 1.hour.ago)
    sign_in @author
    data = card(secret)

    assert data["author"]["anonymous"]
    assert_equal "Anonymous", data["author"]["name"]
    assert_nil data["author"]["username"]
    assert_nil data["author"]["avatar_url"]
    assert_equal AccentPalette.for(nil)[:accent], data["accent"]
    assert_equal short_post_url(code: secret.id.to_s(36)), data["link"], "the author's own ref would unmask them"
    assert_not_includes response.body, "card_author"
  end

  test "only public breaths can become images" do
    draft = Post.create!(user: @author, title: "Draft", content: "Not yet", status: :draft)
    held = Post.create!(user: @author, title: "Held", content: "Held", status: :published,
                        moderation_status: :pending_review, published_at: 1.hour.ago)
    sign_in @author
    [ draft, held ].each do |post|
      get post_share_card_path(post)
      assert_response :not_found
    end
  end

  test "long breaths are clipped and marked" do
    long = Post.create!(user: @author, title: "Long", content: "word " * 1_000, status: :published,
                        moderation_status: :approved, published_at: 1.hour.ago)
    data = card(long)
    assert data["truncated"]
    assert_operator data["text"].length, :<=, ShareCard::TEXT_LIMIT + 1
    assert data["text"].end_with?("…")
  end

  test "a shared thread only carries replies that may travel" do
    fan = create_member("fan_reply")
    blocked_by_sharer = create_member("blocked_by_sharer")
    blocker = create_member("blocks_sharer")
    gone = create_member("gone_replier", active: false)
    kid = create_member("kid_replier")
    kid.profile.update!(birth_year: Date.current.year - 14)
    banned = create_member("banned_replier")
    banned.risk_profile.update!(risk_level: :banned)
    MessageBlock.create!(blocker: @sharer, blocked: blocked_by_sharer)
    MessageBlock.create!(blocker: blocker, blocked: @sharer)

    good = reply(fan, "This is so true, thank you", likes: 3)
    reply(blocked_by_sharer, "From someone the sharer blocked", likes: 50)
    reply(blocker, "From someone who blocked the sharer", likes: 50)
    reply(gone, "From a deactivated account", likes: 50)
    reply(kid, "From a teenager", likes: 50)
    reply(banned, "From a banned account", likes: 50)
    reply(create_member("held_replier"), "Held for review", likes: 50, moderation_status: :pending_review)
    reply(create_member("flagged_replier"), "Flagged by members", likes: 50, flagged: true)
    reply(create_member("deleted_replier"), "Deleted later", likes: 50, deleted_at: Time.current)

    sign_in @sharer
    data = card(thread: 1)

    assert_equal [ good.id ], data["reply_candidates"].map { _1["id"] }
    assert_equal [ good.id ], data["replies"].map { _1["id"] }
    assert_equal "fan_reply", data["replies"].first["author"]["username"]
    assert_not data["can_choose_replies"]
    %w[blocked_by_sharer blocks_sharer gone_replier kid_replier banned_replier Held Flagged Deleted].each do |hidden|
      assert_not_includes response.body, hidden
    end
  end

  test "the author of an anonymous breath stays anonymous in its replies" do
    secret = Post.create!(user: @author, title: "Please pray", content: "Hard week.", anonymous: true,
                          status: :published, moderation_status: :approved, published_at: 1.hour.ago)
    reply(@author, "Thank you all for praying", post: secret, likes: 9)
    reply(create_member("kind_friend"), "Praying for you today", post: secret, likes: 2)

    sign_in @sharer
    data = card(secret, thread: 1)
    masked = data["replies"].first

    assert masked["author"]["anonymous"]
    assert_equal "Anonymous (author)", masked["author"]["name"]
    assert_nil masked["author"]["username"]
    assert_not_includes response.body, "card_author"
    assert_equal "kind_friend", data["replies"].second["author"]["username"]
  end

  test "most-liked replies go first, at most four, and the author may pick others" do
    replies = (1..6).map { |i| reply(create_member("replier_#{i}"), "Reply number #{i} here", likes: i) }

    sign_in @sharer
    data = card(thread: 1, replies: replies.first(2).map(&:id).join(","))
    assert_equal replies.last(4).reverse.map(&:id), data["replies"].map { _1["id"] }, "only the author chooses"

    sign_in @author
    data = card(thread: 1, replies: [ replies[0].id, replies[1].id, 999_999 ].join(","))
    assert data["can_choose_replies"]
    assert_equal [ replies[0].id, replies[1].id ], data["replies"].map { _1["id"] }
  end

  test "a breath in a series says which part it is" do
    series = @author.series.create!(title: "Who Is a Teenager?")
    parts = (1..3).map do |i|
      Post.create!(user: @author, title: "Who Is a Teenager? (#{i})", content: "Part #{i}.", status: :published,
                   moderation_status: :approved, published_at: 1.hour.ago, series: series)
    end
    assert_equal "Part 2 of 3 · Who Is a Teenager?", card(parts.second)["series"]
  end

  test "QR codes are only made for this site's own addresses" do
    get share_qr_path(url: "http://www.example.com/series/abc?ref=card_sharer")
    assert_response :success
    assert response.parsed_body["qr"].first.match?(/\A[01]+\z/)

    [ "https://evil.example.org/phish", "javascript:alert(1)", "not a url" ].each do |url|
      get share_qr_path(url: url)
      assert_response :unprocessable_entity
    end
  end

  test "the share menu offers a thread only when there are replies" do
    sign_in @sharer
    get post_path(@post)
    assert_select ".fc-share-menu button", text: /Snapshot for status/
    assert_select ".fc-share-menu button", text: /Share as thread/, count: 0

    reply(create_member("first_reply"), "A first reply to this")
    get post_path(@post)
    assert_select ".fc-share-menu button", text: /Share as thread/
  end
end
