# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The Updates tab: bots that bring in news, sport, jobs and free courses.
class UpdatesBotsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  RSS = <<~XML
    <?xml version="1.0"?>
    <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
      <channel>
        <item>
          <title>Scientists find water on a distant moon</title>
          <link>https://news.example.org/moon-water?utm_source=rss</link>
          <description>&lt;p&gt;A new probe found &lt;b&gt;ice&lt;/b&gt; under the surface.&lt;/p&gt;</description>
          <media:thumbnail url="https://img.example.org/moon.jpg"/>
          <pubDate>#{1.hour.ago.rfc2822}</pubDate>
        </item>
        <item>
          <title>Best betting odds for the weekend</title>
          <link>https://news.example.org/odds</link>
          <description>Our tips.</description>
          <pubDate>#{1.hour.ago.rfc2822}</pubDate>
        </item>
      </channel>
    </rss>
  XML

  ATOM = <<~XML
    <?xml version="1.0"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <title>Learn Python for free – full course</title>
        <link rel="alternate" href="https://learn.example.org/python"/>
        <summary>A free 10-hour course.</summary>
        <updated>#{2.hours.ago.iso8601}</updated>
      </entry>
    </feed>
  XML

  REMOTIVE = {
    jobs: [ { title: "Support Engineer", url: "https://jobs.example.org/1", company_name: "Acme",
              candidate_required_location: "Worldwide", salary: "$50k", job_type: "full_time",
              description: "<p>Help customers.</p>", company_logo: "https://img.example.org/acme.png",
              publication_date: 3.hours.ago.iso8601 } ]
  }.to_json

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_bots", email: "ada-bots@example.com", password: @pass, password_confirmation: @pass)
    @news = BotSource.create!(bot: "news", topic: "science", name: "Example News", url: "https://news.example.org/rss")
    @learn = BotSource.create!(bot: "courses", name: "Example Learn", url: "https://learn.example.org/atom")
    @jobs = BotSource.create!(bot: "jobs", name: "Example Jobs", url: "https://jobs.example.org/api", format: "remotive")
  end

  def feeds
    { @news.url => RSS, @learn.url => ATOM, @jobs.url => REMOTIVE }
  end

  def with_feeds(&block)
    Bots::Http.stub(:get, ->(url, **) { feeds.fetch(url) { raise Bots::Http::Error, "no page" } }, &block)
  end

  def item_for(source, title:, bot: source.bot, status: :live)
    BotItem.create!(bot_source: source, bot: bot, topic: source.topic, title: title, summary: "A summary.",
                    url: "https://x.example.org/#{SecureRandom.hex(4)}", url_digest: SecureRandom.hex(16),
                    status: status, published_at: 1.hour.ago)
  end

  # ── Reading feeds ──

  test "RSS, Atom and job APIs become clean candidates" do
    with_feeds do
      rss = Bots::Reader.call(@news)
      assert_equal "Scientists find water on a distant moon", rss.first.title
      assert_equal "A new probe found ice under the surface.", rss.first.text
      assert_equal "https://img.example.org/moon.jpg", rss.first.image_url

      atom = Bots::Reader.call(@learn)
      assert_equal "https://learn.example.org/python", atom.first.url

      job = Bots::Reader.call(@jobs).first
      assert_equal({ "company" => "Acme", "location" => "Worldwide", "salary" => "$50k", "type" => "full_time" }, job.details)
    end
  end

  test "the same story with tracking params is one link" do
    assert_equal BotItem.digest_for("https://a.org/story?utm_source=x#top"), BotItem.digest_for("https://a.org/story")
  end

  test "feeds are only read over https from public hosts" do
    assert_raises(Bots::Http::Error) { Bots::Http.get("http://example.org/feed") }
    assert_raises(Bots::Http::Error) { Bots::Http.get("https://localhost/feed") }
    assert_raises(Bots::Http::Error) { Bots::Http.get("https://127.0.0.1/feed") }
  end

  # ── Choosing what to post ──

  test "a run posts fresh, fit stories and never the same link twice" do
    with_feeds do
      Bots::ImageFinder.stub(:call, nil) do
        result = Bots::Refresh.call("news", force: true)
        assert_equal 1, result.posted
        assert_equal 0, Bots::Refresh.call("news", force: true).posted
      end
    end

    item = BotItem.live.sole
    assert_equal "Scientists find water on a distant moon", item.title
    assert_equal "science", item.topic
    assert BotItem.where("title ILIKE ?", "%betting%").none?, "gambling never gets in"
  end

  test "the AI editor's picks and summaries are used, and the rest are skipped" do
    answer = { "content" => [ { "type" => "text", "text" => { picks: [ { id: 1, summary: "A probe found ice under a moon's surface." } ] }.to_json } ] }
    Ai::Moderation::Client.stub(:stub?, false) do
      Ai::Moderation::Client.stub(:call, answer) do
        with_feeds { Bots::ImageFinder.stub(:call, nil) { Bots::Refresh.call("news", force: true) } }
      end
    end

    assert_equal "A probe found ice under a moon's surface.", BotItem.live.sole.summary
  end

  test "when the AI fails the bots still post, carefully" do
    Ai::Moderation::Client.stub(:stub?, false) do
      Ai::Moderation::Client.stub(:call, ->(**) { raise Ai::Moderation::Client::ApiError, "503" }) do
        with_feeds { Bots::ImageFinder.stub(:call, nil) { Bots::Refresh.call("news", force: true) } }
      end
    end
    assert_equal 1, BotItem.live.count
  end

  test "each bot keeps to its daily limit" do
    cap = Bots::Catalog.fetch("courses").daily_cap
    cap.times { |i| item_for(@learn, title: "Course #{i}") }
    with_feeds { assert_equal 0, Bots::Refresh.call("courses", force: true).posted }
  end

  test "jobs that ask applicants to pay are never posted" do
    scam = Bots::Reader::Candidate.new(title: "Data entry, pay registration fee to start", url: "https://j.example.org/2",
                                       text: "", published_at: Time.current, details: {})
    fine = Bots::Reader::Candidate.new(title: "Backend Engineer", url: "https://j.example.org/3",
                                       text: "Build APIs.", published_at: Time.current, details: {})
    picks = Bots::Editor.call(bot: "jobs", candidates: [ [ scam, @jobs ], [ fine, @jobs ] ], pick: 5)
    assert_equal [ "Backend Engineer" ], picks.map { |p| p.candidate.title }
  end

  test "offline picks don't post one story twice from two outlets" do
    other = BotSource.create!(bot: "news", topic: "world", name: "Other", url: "https://other.example.org/rss")
    a = Bots::Reader::Candidate.new(title: "West Ham confirm Parker as head coach", url: "https://a.example.org/1", text: "", published_at: Time.current, details: {})
    b = Bots::Reader::Candidate.new(title: "Parker appointed West Ham head coach", url: "https://b.example.org/1", text: "", published_at: Time.current, details: {})
    picks = Bots::Editor.call(bot: "news", candidates: [ [ a, @news ], [ b, other ] ], pick: 5)
    assert_equal 1, picks.size
  end

  # ── The Updates tab ──

  test "the Updates tab shows the bots' items, filters, and leaves Recent alone" do
    item_for(@news, title: "Water on a distant moon")
    item_for(@jobs, title: "Support Engineer")
    item_for(@news, title: "Hidden by an admin", status: :hidden)
    sign_in @ada

    get feed_updates_path
    assert_response :success
    assert_select ".fc-tab.is-active", text: "Updates"
    assert_select ".fc-bot-card", 2
    assert_select ".fc-bot-title", text: "Hidden by an admin", count: 0
    assert_select ".fc-bot-safety", 1 # job cards carry the never-pay line

    get feed_updates_path(bot: "news", topic: "science")
    assert_select ".fc-bot-card", 1
    assert_select ".fc-bot-chip.is-active", text: "Science & discoveries"

    get feed_path
    assert_select ".fc-bot-card", 0
  end

  test "members choose which bots they see" do
    item_for(@news, title: "Water on a distant moon")
    item_for(@jobs, title: "Support Engineer")
    sign_in @ada

    patch settings_updates_path, params: { bots: %w[jobs courses] }
    assert_equal %w[news sports], @ada.reload.hidden_bots
    follow_redirect!
    assert_select ".fc-bot-title", text: "Support Engineer"
    assert_select ".fc-bot-title", text: "Water on a distant moon", count: 0
  end

  test "members can react to an update, and nobody gets a notification" do
    item = item_for(@news, title: "Water on a distant moon")
    sign_in @ada

    assert_no_difference -> { Notification.count } do
      post likes_path(likeable_type: "BotItem", likeable_id: item.id, reaction_emoji: "😮"),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal 1, item.reload.likes_count
    assert_match dom_id(item, :reactions), response.body
  end

  test "a hidden update can't be reacted to" do
    item = item_for(@news, title: "Hidden", status: :hidden)
    sign_in @ada
    post likes_path(likeable_type: "BotItem", likeable_id: item.id, reaction_emoji: "😮")
    assert_equal 0, item.reload.likes_count
  end

  # ── Admin ──

  test "admins see sources and can switch one off or hide an item" do
    admin = User.create!(username: "boss_bots", email: "boss-bots@example.com", password: @pass, password_confirmation: @pass, role: :admin)
    item = item_for(@news, title: "Water on a distant moon")
    sign_in admin

    get admin_bots_path
    assert_response :success
    assert_select "p", text: /Example News/

    patch admin_toggle_bot_source_path(@news)
    assert_not @news.reload.active
    patch admin_toggle_bot_item_path(item)
    assert item.reload.hidden?
  end

  test "members can't open the bots admin" do
    sign_in @ada
    get admin_bots_path
    assert_redirected_to root_path
  end
end
