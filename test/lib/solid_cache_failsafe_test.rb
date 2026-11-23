# frozen_string_literal: true

require "test_helper"

# Production's Solid Cache broke (Nov 2026); a cache error must read as a miss.
class SolidCacheFailsafeTest < ActiveSupport::TestCase
  test "any error inside a Solid Cache call is a miss, not an exception" do
    store = SolidCache::Store.new
    broken = ->(*) { raise ActiveRecord::StatementInvalid, "relation solid_cache_entries does not exist" }

    SolidCache::Entry.stub(:read, broken) do
      SolidCache::Entry.stub(:write, broken) do
        assert_nil store.read("feed-sidebar")
        assert_equal "fresh", store.fetch("feed-sidebar") { "fresh" }
        assert_not store.write("post_view/1/2", true, unless_exist: true)
      end
    end
  end
end
