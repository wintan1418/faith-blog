# frozen_string_literal: true

module SiteSearch
  # Breath search, built to stay fast at millions of rows:
  #
  # 1. Candidates. Matching ids come from the GIN index, newest first, capped
  #    at CANDIDATES. A rare word returns all its matches straight from the
  #    index; a very common word walks the published_at index and stops after
  #    CANDIDATES hits, so we never rank (or count) a huge match set. Exact
  #    title matches and breaths whose replies match join the candidates
  #    through their own indexes.
  # 2. Rank only the candidates: ts_rank_cd over the weighted vector (title A,
  #    text B, author C, room D), an exact-title bonus, and gentle boosts for
  #    likes/replies and recency.
  # 3. Load the page's breaths and build highlighted snippets for those 20
  #    only (Highlighter).
  #
  # The count is "N" up to the cap, then "1,000+".
  class PostSearch
    CANDIDATES = 1000
    REPLY_CANDIDATES = 300
    PER_PAGE = 20
    SORTS = %w[relevance newest loved].freeze
    DATES = { "week" => 1.week, "month" => 1.month, "year" => 1.year }.freeze
    TYPES = %w[text photo voice].freeze

    Hit = Struct.new(:post, :score, :reply_only, :title_html, :snippet_html, :reply_html, keyword_init: true)

    class Result
      attr_reader :hits, :total, :page, :per_page

      def initialize(hits:, total:, page:, per_page:, capped:)
        @hits = hits
        @total = total
        @page = page
        @per_page = per_page
        @capped = capped
      end

      def capped? = @capped
      def empty? = hits.empty?
      def posts = hits.map(&:post)
      def pages = [ (total.to_f / per_page).ceil, 1 ].max
      def next_page = page < pages ? page + 1 : nil
      def prev_page = page > 1 ? page - 1 : nil
    end

    EMPTY = Result.new(hits: [], total: 0, page: 1, per_page: PER_PAGE, capped: false).freeze

    attr_reader :query, :visibility, :filters

    # filters: room (Room), since (Time), type ("text"/"photo"/"voice"),
    # author (User, from:), sort.
    def initialize(query, visibility:, filters: {})
      @query = query
      @visibility = visibility
      @filters = filters
    end

    def sort = SORTS.include?(filters[:sort].to_s) ? filters[:sort].to_s : "relevance"

    def call(page: 1, per_page: PER_PAGE, snippets: true, include_replies: true)
      return EMPTY if blocked_by_filters? || !query.searchable?

      page = page.to_i.clamp(1, [ CANDIDATES / per_page, 1 ].max)
      rows = ActiveRecord::Base.connection.select_rows(page_sql(page:, per_page:, include_replies:))
      return EMPTY if rows.empty?

      total = rows.first[3].to_i
      posts = load_posts(rows.map { |r| r[0].to_i })
      hits = rows.filter_map do |id, score, post_match, _total|
        post = posts[id.to_i] or next
        Hit.new(post: post, score: score.to_f, reply_only: !ActiveModel::Type::Boolean.new.cast(post_match))
      end
      Highlighter.new(query, visibility).decorate(hits) if snippets
      Result.new(hits: hits, total: total, page: page, per_page: per_page, capped: total >= CANDIDATES)
    end

    # Breaths whose title is close to what was typed (pg_trgm word
    # similarity), for queries the full-text search found little for.
    def fuzzy_titles(limit: 6)
      return [] if query.plain_text.length < 3 || blocked_by_filters?

      key = "public.search_key(#{conn.quote(query.plain_text)})"
      sql = <<~SQL
        SELECT p.id FROM posts p
        WHERE #{key} <% p.search_title AND #{visibility.posts_sql} #{filters_sql}
        ORDER BY word_similarity(#{key}, p.search_title) DESC, p.published_at DESC
        LIMIT #{limit.to_i}
      SQL
      ids = conn.select_values(sql).map(&:to_i)
      posts = load_posts(ids)
      hits = ids.filter_map { |id| posts[id] && Hit.new(post: posts[id], score: 0, reply_only: false) }
      Highlighter.new(query, visibility).decorate(hits)
      hits
    end

    def page_sql(page:, per_page:, include_replies: true)
      vis = visibility.posts_sql("p")
      key = "left(public.search_key(#{conn.quote(query.plain_text.first(512))}), 512)"
      ctes = [ <<~SQL ]
        post_hits AS MATERIALIZED (
          SELECT p.id FROM posts p
          WHERE p.searchable @@ #{tsquery_sql} AND #{vis} #{filters_sql}
          ORDER BY p.published_at DESC LIMIT #{CANDIDATES})
      SQL
      sources = [ "SELECT id FROM post_hits" ]
      if query.plain_text.present?
        ctes << <<~SQL
          title_hits AS (
            SELECT p.id FROM posts p
            WHERE left(p.search_title, 512) = #{key} AND #{vis} #{filters_sql} LIMIT 20)
        SQL
        sources << "SELECT id FROM title_hits"
      end
      if include_replies
        # Replies only matter when the breaths themselves matched little: a
        # reply-only match never outranks a direct one. When the breath
        # candidates are already full, this branch is skipped outright.
        ctes << <<~SQL
          reply_hits AS MATERIALIZED (
            SELECT c.post_id FROM comments c
            WHERE (SELECT count(*) FROM post_hits) < #{CANDIDATES}
              AND c.searchable @@ #{tsquery_sql} AND #{visibility.comments_sql('c')}
            ORDER BY c.created_at DESC LIMIT #{REPLY_CANDIDATES}),
          reply_posts AS (
            SELECT p.id FROM posts p
            WHERE p.id IN (SELECT post_id FROM reply_hits) AND #{vis} #{filters_sql})
        SQL
        sources << "SELECT id FROM reply_posts"
      end

      <<~SQL
        WITH #{ctes.join(', ')},
        candidates AS MATERIALIZED (#{sources.join(' UNION ')})
        SELECT p.id, #{score_sql(key)} AS score, (p.searchable @@ #{tsquery_sql}) AS post_match,
               count(*) OVER () AS total
        FROM candidates JOIN posts p ON p.id = candidates.id
        ORDER BY #{order_sql}
        LIMIT #{per_page.to_i} OFFSET #{(page - 1) * per_page.to_i}
      SQL
    end

    def tsquery_sql
      @tsquery_sql ||= "to_tsquery('#{Schema::CONFIG}'::regconfig, #{conn.quote(query.tsquery)})"
    end

    private

    def conn = ActiveRecord::Base.connection

    # A room the viewer can't see, or a from: member they can't see, finds nothing.
    def blocked_by_filters?
      filters.key?(:author) && filters[:author].nil? ||
        filters.key?(:room) && filters[:room].nil?
    end

    def score_sql(key)
      # ts_rank_cd: weights for D, C, B, A; normalization 1 = divide by
      # 1 + log(length), so long threads don't win on volume alone.
      <<~SQL.squish
        ((CASE WHEN p.searchable @@ #{tsquery_sql}
               THEN ts_rank_cd('{0.1, 0.2, 0.4, 1.0}', p.searchable, #{tsquery_sql}, 1) ELSE 0.01 END)
         + (CASE WHEN left(p.search_title, 512) = #{key} THEN 1.0 ELSE 0 END))
        * (1 + 0.08 * ln(1 + p.likes_count + 2 * p.comments_count))
        / power(1 + GREATEST(EXTRACT(EPOCH FROM statement_timestamp() - p.published_at), 0) / 31557600.0, 0.3)
      SQL
    end

    def order_sql
      case sort
      when "newest" then "p.published_at DESC, p.id DESC"
      when "loved" then "p.likes_count DESC, p.published_at DESC, p.id DESC"
      else "score DESC, p.published_at DESC, p.id DESC"
      end
    end

    def filters_sql
      @filters_sql ||= begin
        parts = []
        parts << "p.room_id = #{filters[:room].id.to_i}" if filters[:room]
        if filters[:author]
          # from: never matches an anonymous breath — that would unmask it.
          parts << "p.user_id = #{filters[:author].id.to_i} AND NOT p.anonymous AND p.page_id IS NULL"
        end
        parts << "p.published_at >= #{conn.quote(filters[:since])}" if filters[:since]
        case filters[:type].to_s
        when "photo" then parts << attachment_exists("images")
        when "voice" then parts << attachment_exists("voice_note")
        when "text" then parts << "NOT #{attachment_exists('images')} AND NOT #{attachment_exists('voice_note')}"
        end
        parts.empty? ? "" : "AND #{parts.join(' AND ')}"
      end
    end

    def attachment_exists(name)
      "EXISTS (SELECT 1 FROM active_storage_attachments asa WHERE asa.record_type = 'Post' " \
        "AND asa.record_id = p.id AND asa.name = '#{name}')"
    end

    def load_posts(ids)
      Post.where(id: ids)
          .includes(:room, :rich_text_content, :voice_note_attachment, { images_attachments: :blob },
                    { user: { profile: { avatar_attachment: :blob } } })
          .index_by(&:id)
    end
  end
end
