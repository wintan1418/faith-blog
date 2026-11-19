# frozen_string_literal: true

# Where sign-in / sign-up rate-limit and bot counters live: the app cache
# (Solid Cache in production, shared by every process). Test runs use a
# null cache, so they get an in-memory store instead (cleared per test).
module AuthThrottleStore
  module_function

  def store
    @store ||= Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end

  def clear!
    store.clear if store.is_a?(ActiveSupport::Cache::MemoryStore)
  end
end
