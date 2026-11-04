# frozen_string_literal: true

module Bots
  # The bots' editor: from a pile of fresh candidates, choose the few worth a
  # member's time, keep anything unfit out, and write a short neutral summary.
  # Uses the same AI as moderation; when that's unavailable, a careful local
  # pick (block-list + freshest, spread across sources) keeps the tab alive.
  class Editor
    TASK_MARKER = "[TASK:BOT_EDITOR]"
    MAX_PICKS = 5 # the AI answer is capped at ~600 tokens

    Pick = Data.define(:candidate, :summary)

    # Never posted, whatever the AI says (also the offline filter).
    BLOCKED = /\b(?:porn\w*|nude\w*|naked|sex(?:y|ual(?:ly)?)?|onlyfans|escort\w*|erotic\w*|strip\s?club|casino\w*|betting|bet(?:s|ting)?\s+(?:tips|odds)|gambl\w*|sportsbook|odds\s+boost|lottery|crypto\s+(?:signals|giveaway)|get\s+rich|forex\s+signals|occult|witchcraft|horoscope\w*|astrolog\w*|tarot)\b/i
    # Job/course red flags: paying to apply is a scam on any continent.
    SCAMMY = /\b(?:application\s+fee|registration\s+fee|pay\s+(?:to|before)\s+(?:apply|start)|processing\s+fee|mlm|network\s+marketing|commission[-\s]only)\b/i

    BEATS = {
      "news" => "global general news: world affairs, politics, technology and AI, science and discoveries, health, business, food and faith. Prefer stories of wide international interest; keep a balance of regions and topics, never several picks about the same story.",
      "sports" => "general sport worldwide: football, basketball, cricket, tennis, athletics, rugby, F1 and more. Prefer results, big moments and inspiring stories; avoid transfer gossip and rumour.",
      "jobs" => "remote jobs open to people around the world. Prefer roles open to any country, with a clear employer and role. Skip roles that are only for one country unless clearly remote-friendly.",
      "courses" => "free learning: free courses, free certificates, scholarships, fellowships and grants open internationally. Skip paid-only courses and anything that is just a news article about education."
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      #{TASK_MARKER}
      You are the editor for the Updates tab of Brethreign, a global Christian
      community with members from every country. Members are adults and
      families; politics and news are welcome, told fairly.

      From the numbered candidates, choose the best ones for the beat you are
      given, up to the number asked (fewer is fine; none is fine).

      Never choose:
      - sexual or explicit content, graphic violence or gore described in detail;
      - gambling, betting odds, casinos, lotteries, get-rich or crypto schemes;
      - occult, horoscopes, astrology, tarot;
      - celebrity gossip, clickbait, rumours, adverts, sponsored or "deals" posts;
      - opinion pieces that mock a faith, people group or political side;
      - for jobs and courses: anything asking applicants to pay, MLM, commission-only.

      For each choice write a summary: one or two plain, neutral sentences,
      at most 220 characters, in your own words (no quotes from the article),
      saying what happened or what is on offer. For politics, report facts
      without taking sides.

      Return ONLY JSON, no prose, no markdown fences:
      {"picks":[{"id":<candidate number>,"summary":"<summary>"}]}
    PROMPT

    def self.call(...) = new(...).call

    # candidates: [[Candidate, BotSource], ...]
    def initialize(bot:, candidates:, pick:)
      @bot = bot
      @candidates = candidates.reject { |c, _| unfit?(c) }
      @pick = pick.clamp(0, MAX_PICKS)
    end

    attr_reader :mode

    def call
      return [] if @pick.zero? || @candidates.empty?

      if Ai::Moderation::Client.stub?
        @mode = :local
        return local_picks
      end

      @mode = :ai
      ai_picks
    rescue Ai::Moderation::Client::Error, JSON::ParserError, KeyError, TypeError => e
      Rails.logger.warn("[bots] editor fell back to local picks for #{@bot}: #{e.class}: #{e.message}")
      @mode = :local
      local_picks
    end

    # Candidates the editor saw: everything not picked is skipped next time.
    def considered = @candidates.map(&:first)

    private

    def unfit?(candidate)
      text = "#{candidate.title} #{candidate.text}"
      text.match?(BLOCKED) || (%w[jobs courses].include?(@bot) && text.match?(SCAMMY)) ||
        CleanLanguage.offensive?(candidate.title)
    end

    def ai_picks
      raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
      text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
      text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
      picks = Array(JSON.parse(text).fetch("picks"))

      picks.first(@pick).filter_map do |p|
        candidate = @candidates[p["id"].to_i - 1]&.first
        next unless candidate

        Pick.new(candidate: candidate, summary: p["summary"].to_s.squish.truncate(240))
      end.uniq { |p| p.candidate.url }
    end

    def user_prompt
      lines = @candidates.each_with_index.map do |(c, source), i|
        topic = source.topic ? " [#{source.topic}]" : ""
        detail = c.details.presence && " (#{c.details.values.join(', ')})"
        "#{i + 1}. #{source.name}#{topic}: #{c.title}#{detail}\n   #{c.text.to_s.truncate(260)}"
      end
      "#{TASK_MARKER}\nBeat: #{BEATS.fetch(@bot)}\nChoose up to #{@pick}.\n\nCandidates:\n#{lines.join("\n")}"
    end

    # Freshest first, one per source in turn, so no outlet dominates.
    def local_picks
      by_source = @candidates.group_by { |_, source| source.id }.values
                             .map { |list| list.sort_by { |c, _| -c.published_at.to_i } }
      chosen = []
      until chosen.size >= @pick || by_source.all?(&:empty?)
        by_source.each do |list|
          break if chosen.size >= @pick
          (c, _) = list.shift
          chosen << c if c && chosen.none? { |other| same_story?(c, other) }
        end
      end
      chosen.map { |c| Pick.new(candidate: c, summary: c.text.to_s.truncate(220).presence) }
    end

    # Two outlets, one story: most of the title's longer words in common.
    def same_story?(a, b)
      words = ->(c) { c.title.downcase.scan(/[[:alnum:]]{4,}/).to_set }
      wa, wb = words.(a), words.(b)
      return false if wa.empty? || wb.empty?
      (wa & wb).size.to_f / [ wa.size, wb.size ].min >= 0.6
    end
  end
end
