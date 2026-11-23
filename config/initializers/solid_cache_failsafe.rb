# frozen_string_literal: true

# Solid Cache only swallows "transient" database errors (timeouts, deadlocks).
# Anything else — a missing cache table, a bad connection config — raised out
# of every Rails.cache call: the post page (view counting), rate limits, error
# alerts, the feed sidebar. A cache must never take a page down, so any error
# inside the store is logged and treated as a miss / failed write instead.
module SolidCacheFailsafe
  private

  def failsafe(method, returning: nil)
    super
  rescue StandardError => error
    ActiveSupport.error_reporter&.report(error, handled: true, severity: :warning)
    Rails.logger.error("[SolidCache] #{method} failed, returned #{returning.inspect}: #{error.class}: #{error.message}")
    returning
  end
end

SolidCache::Store.prepend(SolidCacheFailsafe)
