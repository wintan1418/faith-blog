# frozen_string_literal: true

module Bots
  # One run for one bot: read its sources, keep what's fresh and unseen, let
  # the editor choose within today's allowance, and post the choices.
  class Refresh
    PER_SOURCE = 12             # freshest unseen entries per source per run
    CHUNK = 8                   # candidates per AI call (its answer is capped at ~600 tokens)
    # Most one hourly run may add, so a big batch arrives spread over the day.
    PER_RUN = { "news" => 60, "sports" => 25, "jobs" => 25, "courses" => 15 }.freeze
    KEEP_SKIPPED_FOR = 7.days   # long enough that old links aren't reconsidered
    KEEP_LIVE_FOR = 45.days

    Result = Data.define(:bot, :posted, :mode, :errors)

    def self.call(bot_key, force: false) = new(bot_key, force: force).call

    def initialize(bot_key, force: false)
      @bot = Catalog.fetch(bot_key)
      @force = force
    end

    # Everything fresh and fit gets in (within the run's and the day's ceiling).
    # Candidates go to the editor a few at a time, topic by topic in turn, so
    # every topic is heard before any topic gets a second turn.
    def call
      errors = []
      candidates = gather(errors)
      by_url = candidates.to_h { |c, source| [ c.url, source ] }
      budget = allowance
      posted = []
      modes = []
      recent = recent_titles

      chunks = candidates.group_by { |_, source| source.topic }.values.map { |group| group.each_slice(CHUNK).to_a }
      round_robin(chunks).each do |chunk|
        break if budget <= 0

        editor = Editor.new(bot: @bot.key, candidates: chunk, pick: [ budget, Editor::MAX_PICKS ].min)
        picks = editor.call
        modes << editor.mode
        fresh = picks.reject { |p| Editor.same_story_as_any?(p.candidate.title, recent) }
        added = fresh.filter_map { |p| post(p, by_url.fetch(p.candidate.url)) }
        posted += added
        recent += added.map(&:title)
        budget -= added.size
        # Only an AI pass has judged the rest; offline picks leave them for later.
        added_urls = added.map(&:url).to_set
        skip(editor.considered.reject { |c| added_urls.include?(c.url) }, by_url) if editor.mode == :ai
      end

      Result.new(bot: @bot.key, posted: posted.size, mode: modes.uniq.join("+").presence&.to_sym, errors: errors)
    end

    # Old items go so the tables stay small.
    def self.prune!
      BotItem.skipped.where(created_at: ...KEEP_SKIPPED_FOR.ago).delete_all
      old = BotItem.where.not(status: :skipped).where(published_at: ...KEEP_LIVE_FOR.ago)
      Like.where(likeable_type: "BotItem", likeable_id: old.select(:id)).delete_all
      old.delete_all
    end

    private

    # What this run may still add: the day's ceiling, at most PER_RUN at once.
    def allowance
      posted_today = BotItem.where(bot: @bot.key, status: [ :live, :hidden ])
                            .where(created_at: Time.current.beginning_of_day..).count
      remaining = [ @bot.daily_cap - posted_today, 0 ].max
      @force ? remaining : [ remaining, PER_RUN.fetch(@bot.key) ].min
    end

    # Titles posted lately, so another outlet's take on the same story is skipped.
    def recent_titles
      BotItem.where(bot: @bot.key, status: [ :live, :hidden ], created_at: 2.days.ago..).pluck(:title)
    end

    # [[a1, a2], [b1]] -> [a1, b1, a2]
    def round_robin(lists)
      lists = lists.map(&:dup)
      out = []
      out.concat(lists.filter_map(&:shift)) until lists.all?(&:empty?)
      out
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
