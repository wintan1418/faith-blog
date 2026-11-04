# frozen_string_literal: true

# Every hour: each Updates bot reads its sources and posts what it chose.
# One bot failing never stops the others.
class BotsRefreshJob < ApplicationJob
  queue_as :default

  def perform(bot = nil, force: false)
    keys = bot ? [ bot ] : Bots::Catalog.keys
    keys.each do |key|
      result = Bots::Refresh.call(key, force: force)
      Rails.logger.info("[bots] #{key}: posted #{result.posted} (#{result.mode}); #{result.errors.size} source errors")
    rescue StandardError => e
      Rails.logger.error("[bots] #{key} failed: #{e.class}: #{e.message}")
    end
    Bots::Refresh.prune!
  end
end
