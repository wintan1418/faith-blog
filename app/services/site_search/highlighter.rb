# frozen_string_literal: true

module SiteSearch
  # Highlighted titles and snippets for one page of results (never the whole
  # match set): one ts_headline query for every text on the page.
  #
  # Postgres highlights the NFKC-normalized text (so 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿 matches
  # "teenager"), and the highlights are mapped back onto the author's own
  # characters grapheme by grapheme, so styled titles keep their styling.
  # The result is built from escaped text plus our own <mark> tags; nothing
  # Postgres returns is trusted as HTML.
  class Highlighter
    START = "\u{E000}"
    STOP = "\u{E001}"
    FRAGMENT = "\u{E002}"
    MARKERS = /[\u{E000}-\u{E002}]/
    MAX_DOC = 8_000
    SHORT_DOC = 220

    TITLE_OPTIONS = %(HighlightAll=true, StartSel="#{START}", StopSel="#{STOP}").freeze
    BODY_OPTIONS = %(MaxFragments=2, MaxWords=26, MinWords=12, ShortWord=2, StartSel="#{START}", StopSel="#{STOP}", FragmentDelimiter="#{FRAGMENT}").freeze

    # A text in two forms: what the author wrote, and its NFKC form with a
    # map from each normalized character back to the original grapheme.
    class Mapped
      attr_reader :graphemes, :normalized, :owner

      # Every character maps to itself (plain ASCII text).
      IDENTITY = Object.new.tap { |o| o.define_singleton_method(:[]) { |i| i } }.freeze

      def initialize(text)
        text = text.to_s.gsub(MARKERS, "")
        if text.ascii_only?
          @graphemes = text.chars
          @owner = IDENTITY
          @normalized = text
          return
        end

        @graphemes = text.each_grapheme_cluster.to_a
        @owner = []
        buffer = +""
        @graphemes.each_with_index do |g, i|
          piece = g.ascii_only? ? g : normalize(g)
          buffer << piece
          piece.length.times { @owner << i }
        end
        @normalized = buffer
      end

      private

      def normalize(grapheme)
        grapheme.unicode_normalize(:nfkc)
      rescue ArgumentError, Encoding::CompatibilityError
        grapheme
      end
    end

    def initialize(query, visibility)
      @query = query
      @visibility = visibility
    end

    def decorate(hits)
      return hits if hits.empty?

      replies = best_replies(hits.select(&:reply_only).map { |h| h.post.id })
      docs = []
      hits.each do |hit|
        title = hit.post.title.to_s
        docs << [ hit, :title_html, Mapped.new(title), TITLE_OPTIONS ] if title.present?
        body = hit.post.content&.to_plain_text.to_s.first(MAX_DOC)
        docs << [ hit, :snippet_html, Mapped.new(body), options_for(body) ] if body.present?
        reply = replies[hit.post.id].to_s.first(MAX_DOC)
        docs << [ hit, :reply_html, Mapped.new(reply), options_for(reply) ] if reply.present?
      end
      return hits if docs.empty?

      headlines(docs.map { |d| [ d[2].normalized, d[3] ] }).each_with_index do |headline, i|
        hit, field, mapped, = docs[i]
        hit[field] = render(headline.to_s, mapped)
      end
      hits
    end

    # [ [ normalized text, options ], ... ] => headline strings, in order.
    def headlines(pairs)
      conn = ActiveRecord::Base.connection
      texts = conn.quote(PG::TextEncoder::Array.new.encode(pairs.map(&:first)))
      options = conn.quote(PG::TextEncoder::Array.new.encode(pairs.map(&:last)))
      tsquery = conn.quote(@query.tsquery)
      sql = <<~SQL
        SELECT ts_headline('#{Schema::CONFIG}'::regconfig, d.doc, to_tsquery('#{Schema::CONFIG}'::regconfig, #{tsquery}), d.opts)
        FROM unnest(#{texts}::text[], #{options}::text[]) WITH ORDINALITY AS d(doc, opts, ord)
        ORDER BY d.ord
      SQL
      conn.select_values(sql)
    end

    # Turns "a b c  d" into escaped HTML on the original
    # graphemes, with <mark> around each highlight.
    def render(headline, mapped)
      fragments = headline.split(FRAGMENT).map(&:strip).reject { |f| f.delete(START + STOP).blank? }
      cursor = 0
      parts = fragments.map do |fragment|
        plain, ranges = strip_markers(fragment)
        at = mapped.normalized.index(plain, cursor) || mapped.normalized.index(plain)
        if at.nil? || plain.empty?
          html = mark(plain.each_char.to_a, ranges.map { |s, e| [ s, e ] })
          next [ html, false, false ]
        end

        cursor = at + plain.length
        first = mapped.owner[at]
        last = mapped.owner[at + plain.length - 1]
        graphemes = mapped.graphemes[first..last]
        grapheme_ranges = ranges.map { |s, e| [ mapped.owner[at + s] - first, mapped.owner[at + e - 1] - first + 1 ] }
        [ mark(graphemes, grapheme_ranges), first.positive?, last < mapped.graphemes.size - 1 ]
      end
      return ERB::Util.html_escape(mapped.graphemes.first(200).join) if parts.empty?

      html = parts.map.with_index do |(fragment_html, cut_before, cut_after), i|
        lead = cut_before && i.zero? ? "… " : ""
        tail = cut_after ? " …" : ""
        "#{lead}#{fragment_html}#{tail}"
      end.join(" ")
      html.gsub(" … …", " …").html_safe # rubocop:disable Rails/OutputSafety -- built from escaped text and our own <mark> tags
    end

    private

    # Short texts are shown whole; long ones as their best fragments.
    def options_for(text)
      text.length <= SHORT_DOC ? TITLE_OPTIONS : BODY_OPTIONS
    end

    # Text without markers, plus [start, end) ranges of the marked words.
    def strip_markers(fragment)
      plain = +""
      ranges = []
      open = nil
      fragment.each_char do |ch|
        if ch == START
          open = plain.length
        elsif ch == STOP
          ranges << [ open, plain.length ] if open && plain.length > open
          open = nil
        else
          plain << ch
        end
      end
      [ plain, ranges ]
    end

    def mark(chars, ranges)
      starts = ranges.to_h { |s, _| [ s, true ] }
      ends = ranges.to_h { |_, e| [ e, true ] }
      out = +""
      chars.each_with_index do |ch, i|
        out << "</mark>" if ends[i]
        out << "<mark>" if starts[i]
        out << ERB::Util.html_escape(ch)
      end
      out << "</mark>" if ends[chars.size]
      out
    end

    # For breaths that matched only through a reply: the best visible reply.
    def best_replies(post_ids)
      return {} if post_ids.empty?

      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { ids: post_ids.map(&:to_i), q: @query.tsquery } ])
        SELECT DISTINCT ON (c.post_id) c.post_id, c.id FROM comments c
        WHERE c.post_id IN (:ids) AND c.searchable @@ to_tsquery('#{Schema::CONFIG}'::regconfig, :q)
          AND #{@visibility.comments_sql('c')}
        ORDER BY c.post_id, ts_rank_cd(c.searchable, to_tsquery('#{Schema::CONFIG}'::regconfig, :q)) DESC, c.id
      SQL
      pairs = ActiveRecord::Base.connection.select_rows(sql)
      comments = Comment.where(id: pairs.map(&:last)).includes(:rich_text_content).index_by(&:id)
      pairs.to_h do |post_id, comment_id|
        comment = comments[comment_id.to_i]
        [ post_id.to_i, comment && (comment.content&.to_plain_text.presence || comment.read_attribute(:content).to_s) ]
      end
    end
  end
end
