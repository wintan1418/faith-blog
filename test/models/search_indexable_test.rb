# frozen_string_literal: true

require "test_helper"
require_relative "../support/search_indexing_stubs"

# Which changes reach IndexNow's waiting list: public, named, non-prayer
# breaths (when they go live or are edited), public rooms, approved resources,
# active verses. Never private, anonymous, prayer or held breaths.
class SearchIndexableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SearchIndexingStubs

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("seo_author_#{SecureRandom.hex(3)}")
    @room = Room.create!(name: "Seo Room #{SecureRandom.hex(3)}", description: "x", is_public: true)
    @private_room = Room.create!(name: "Seo Hidden #{SecureRandom.hex(3)}", description: "x", is_public: false)
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def breath(**attrs)
    Post.create!({ user: @author, room: @room, title: "Grace #{SecureRandom.hex(3)}", content: "Grace and peace.",
                   status: :published, moderation_status: :approved }.merge(attrs))
  end

  def pending_urls = IndexingPendingUrl.pluck(:url)

  test "a public named breath going live is queued and the batch timer starts" do
    with_indexnow do
      post = nil
      assert_enqueued_with(job: IndexNowFlushJob) { post = breath }
      assert_includes pending_urls, "https://brethreign.com/posts/#{post.slug}"
    end
  end

  test "private-room, anonymous, prayer, draft and held breaths are never queued" do
    with_indexnow do
      breath(room: @private_room)
      breath(anonymous: true)
      breath(prayer_status: :prayer_pending)
      breath(status: :draft)
      breath(moderation_status: :pending_review)
      assert_empty pending_urls.grep(%r{/posts/})
    end
  end

  test "a held breath is queued once moderation releases it" do
    with_indexnow do
      post = breath(moderation_status: :pending_review)
      assert_empty pending_urls.grep(%r{/posts/})
      post.apply_moderation_decision!(:allow)
      assert_includes pending_urls, "https://brethreign.com/posts/#{post.slug}"
    end
  end

  test "edits are queued, counter bumps are not" do
    with_indexnow do
      post = breath
      IndexingPendingUrl.delete_all
      post.update!(likes_count: 5, views_count: 9)
      assert_empty pending_urls

      post.update!(title: "Grace, edited")
      assert_includes pending_urls, "https://brethreign.com/posts/#{post.slug}"

      IndexingPendingUrl.delete_all
      post.update!(anonymous: true)
      assert_empty pending_urls
    end
  end

  test "nothing is queued when IndexNow is off" do
    with_env("INDEXNOW_ENABLED" => "0") do
      assert_no_enqueued_jobs(only: IndexNowFlushJob) { breath }
      assert_empty pending_urls
    end
  end

  test "rooms, resources and verses opt in with their own rules" do
    with_indexnow do
      room = Room.create!(name: "Seo Open #{SecureRandom.hex(3)}", description: "x", is_public: true)
      Room.create!(name: "Seo Closed #{SecureRandom.hex(3)}", description: "x", is_public: false)
      category = ResourceCategory.create!(name: "Seo Guides #{SecureRandom.hex(3)}")
      resource = Resource.create!(user: @author, resource_category: category, title: "Seo guide", resource_type: :link,
                                  url: "https://example.com/a", approved: false)
      assert_equal [ "https://brethreign.com/rooms/#{room.slug}" ], pending_urls.grep(%r{/rooms/})
      assert_empty pending_urls.grep(%r{/resources/})

      resource.update!(approved: true)
      assert_includes pending_urls, "https://brethreign.com/resources/#{resource.slug}"

      BibleVerse.create!(text: "For God so loved the world", reference: "John 3:16", active: true)
      assert_includes pending_urls, "https://brethreign.com/scripture/john-3-16"
    end
  end

  test "recently changed URLs include only indexable pages" do
    with_env("INDEXNOW_ENABLED" => "0") do
      good = breath
      hidden = [ breath(anonymous: true), breath(room: @private_room), breath(prayer_status: :prayer_pending) ]
      urls = SearchIndexing.recently_changed_urls(since: 1.hour.ago)
      assert_includes urls, "https://brethreign.com/posts/#{good.slug}"
      assert_includes urls, "https://brethreign.com/rooms/#{@room.slug}"
      assert_includes urls, "https://brethreign.com/"
      hidden.each { |post| refute_includes urls, "https://brethreign.com/posts/#{post.slug}" }
      refute_includes urls, "https://brethreign.com/rooms/#{@private_room.slug}"
    end
  end

  test "an admin-typed URL must be an indexable page" do
    good = breath
    anon = breath(anonymous: true)
    assert SearchIndexing.submittable_url?("https://brethreign.com/posts/#{good.slug}")
    refute SearchIndexing.submittable_url?("https://brethreign.com/posts/#{anon.slug}")
    refute SearchIndexing.submittable_url?("https://brethreign.com/posts/no-such-breath")
    refute SearchIndexing.submittable_url?("https://brethreign.com/rooms/#{@private_room.slug}")
    refute SearchIndexing.submittable_url?("https://brethreign.com/join/someone")
    assert SearchIndexing.submittable_url?("https://brethreign.com/blog")
  end
end
