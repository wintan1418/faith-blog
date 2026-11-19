# frozen_string_literal: true

# Where request counters for `rate_limit` live: the app cache (Solid Cache in
# production). Tests use a null cache, so they get a private memory store
# instead and clear it between tests.
module RateLimitStore
  def self.store
    @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end
end
