# frozen_string_literal: true

module Bots
  # One run for one bot: read its sources, keep what's fresh and unseen, let
  # the editor choose within today's allowance, and post the choices.
  class Refresh
    RUNS_PER_DAY = 8            # BotsRefreshJob runs every 3 hours
    PER_SOURCE = 6              # freshest unseen entries per source per run
    KEEP_SKIPPED_FOR = 7.days   # long enough that old links aren't reconsidered
    KEEP_LIVE_FOR = 45.days

    Result = Data.define(:bot, :posted, :mode, :errors)

    def self.call(bot_key, force: false) = new(bot_key, force: force).call

    def initialize(bot_key, force: false)
      @bot = Catalog.fetch(bot_key)
      @force = force
    end

    def call
      errors = []
      candidates = gather(errors)
      editor = Editor.new(bot: @bot.key, candidates: candidates, pick: allowance)
      picks = editor.call
      by_url = candidates.to_h { |c, source| [ c.url, source ] }

      posted = picks.filter_map { |pick| post(pick, by_url.fetch(pick.candidate.url)) }
      # Only an AI pass has judged the rest; offline picks leave them for later.
      skip(editor.considered - picks.map(&:candidate), by_url) if editor.mode == :ai

      Result.new(bot: @bot.key, posted: posted.size, mode: editor.mode, errors: errors)
    end

    # Old items go so the tables stay small.
    def self.prune!
      BotItem.skipped.where(created_at: ...KEEP_SKIPPED_FOR.ago).delete_all
      old = BotItem.where.not(status: :skipped).where(published_at: ...KEEP_LIVE_FOR.ago)
      Like.where(likeable_type: "BotItem", likeable_id: old.select(:id)).delete_all
      old.delete_all
    end

    private

    # Today's cap, spread over the day's runs (a manual run may use the rest).
    def allowance
      posted_today = BotItem.where(bot: @bot.key, status: [ :live, :hidden ])
                            .where(created_at: Time.current.beginning_of_day..).count
      remaining = [ @bot.daily_cap - posted_today, 0 ].max
      @force ? remaining : [ remaining, (@bot.daily_cap / RUNS_PER_DAY.to_f).ceil ].min
    end

    def gather(errors)
      BotSource.active.where(bot: @bot.key).flat_map do |source|
        entries = Reader.call(source)
        source.update_columns(last_fetched_at: Time.current, last_error: nil)
        fresh = entries.select { |c| c.published_at.between?(@bot.fresh_for.ago, 1.hour.from_now) }
                       .uniq { |c| BotItem.digest_for(c.url) }
        seen = BotItem.where(url_digest: fresh.map { |c| BotItem.digest_for(c.url) }).pluck(:url_digest).to_set
        fresh.reject { |c| seen.include?(BotItem.digest_for(c.url)) }
             .sort_by { |c| -c.published_at.to_i }.first(PER_SOURCE)
             .map { |c| [ c, source ] }
      rescue Http::Error, JSON::ParserError, Nokogiri::SyntaxError => e
        source.update_columns(last_fetched_at: Time.current, last_error: e.message.truncate(250))
        errors << "#{source.name}: #{e.message}"
        []
      end
    end

    def post(pick, source)
      c = pick.candidate
      image = c.image_url || (ImageFinder.call(c.url) if %w[news sports].include?(@bot.key))
      BotItem.create!(
        bot_source: source, bot: @bot.key, topic: source.topic,
        title: c.title.truncate(250), summary: pick.summary, url: c.url, url_digest: BotItem.digest_for(c.url),
        image_url: image, details: c.details, status: :live, published_at: c.published_at
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.info("[bots] skipped #{c.url}: #{e.message}")
      nil
    end

    def skip(candidates, by_url)
      now = Time.current
      rows = candidates.map do |c|
        { bot_source_id: by_url.fetch(c.url).id, bot: @bot.key, topic: by_url.fetch(c.url).topic,
          title: c.title.truncate(250), url: c.url, url_digest: BotItem.digest_for(c.url), details: {},
          status: BotItem.statuses[:skipped], skip_reason: "not chosen", published_at: c.published_at,
          created_at: now, updated_at: now }
      end
      BotItem.insert_all(rows, unique_by: :url_digest) if rows.any?
    end
  end
end
