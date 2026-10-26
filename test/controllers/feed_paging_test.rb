# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The feed works out each page from ids/times, then loads only that page's cards.
class FeedPagingTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    pw = test_password
    @reader = User.create!(username: "pager", email: "pager@example.com", password: pw)
    @author = User.create!(username: "page_author", email: "page_author@example.com", password: pw)
    room = Room.create!(name: "Paging Room", description: "x", room_type: :general, is_public: true)
    @posts = (1..25).map do |i|
      Post.create!(user: @author, room: room, title: "Breath #{i}", content: "Body #{i}", status: :published,
                   moderation_status: :approved, published_at: (30 - i).hours.ago)
    end
    # A repost of the oldest breath, made just now, should lead the feed.
    @reshare = Reshare.create!(user: @reader, post: @posts.first)
    sign_in @reader
  end

  test "page one: newest first, reposts mixed in by when they were shared, 20 cards" do
    get feed_path

    titles = css_select(".fc-breath-title").map { |e| e.text.strip }
    assert_equal "Breath 1", titles.first, "the fresh repost leads"
    assert_equal "Breath 25", titles.second
  end

  test "page two continues where page one stopped" do
    get feed_path(page: 2), as: :turbo_stream

    assert_response :success
    assert_match "Breath 6", response.body
    assert_no_match(/Breath 25</, response.body)
  end

  test "opening the feed at page two as a full page still works" do
    get feed_path(page: 2)

    assert_response :success
    assert_match "Breath 6", response.body
  end

  test "the feed still loads when the cache store is broken" do
    broken = ->(*) { raise ActiveRecord::StatementInvalid, "relation solid_cache_entries does not exist" }
    Rails.cache.stub(:fetch, broken) do
      get feed_path
    end

    assert_response :success
    assert_match "Breath 25", response.body
  end
end
