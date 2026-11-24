# frozen_string_literal: true

# Spots multi-part writing from titles (see SeriesTitle).
#
#   SeriesSuggestions.for_title(user, "Who Is a Teenager? (7)")
#     # => Suggestion for "Who Is a Teenager?": their existing series, or a
#     #    new one made of the earlier parts they already posted
#
#   SeriesSuggestions.groups
#     # => every (author, base title) run of parts across the site, for
#     #    `rake series:suggest`
module SeriesSuggestions
  # series: an existing Series (or nil to make a new one named `title`);
  # post_ids: the author's earlier parts that would join it.
  Suggestion = Data.define(:series, :title, :part, :post_ids)

  # user, base title, and the posts in it ordered by part number then date.
  Group = Data.define(:user, :key, :title, :posts) do
    def parts = posts.map { |post| SeriesTitle.parse(SeriesTitle.effective_title(post))&.part }
  end

  # How many of an author's titled breaths to look back over.
  LOOKBACK = 500
  # A cheap database pre-filter (titles that might carry a part marker);
  # SeriesTitle.parse makes the real decision. NFKC folds Unicode-bold titles.
  MAYBE_PART_SQL = <<~SQL.squish
    (COALESCE(posts.title, '') <> '' AND normalize(posts.title, NFKC) ~* :hint)
    OR (COALESCE(posts.title, '') = '' AND EXISTS (
      SELECT 1 FROM action_text_rich_texts rt
      WHERE rt.record_type = 'Post' AND rt.record_id = posts.id AND rt.name = 'content'
        AND normalize(left(rt.body, 400), NFKC) ~* :hint))
  SQL
  MARKER_HINT = '(\\(\\s*#?\\s*\\d|part|pt\\.?\\s*\\d|day\\s*\\d|episode|ep\\.?\\s*\\d|#\\s*\\d)'

  module_function

  def for_title(user, title, exclude_post_id: nil)
    parsed = SeriesTitle.parse(title)
    return unless user && parsed&.key

    series = user.series.find { |s| SeriesTitle.key_for(s.title) == parsed.key }
    earlier = candidate_posts(user.posts, exclude_post_id).includes(:series).limit(LOOKBACK)
              .select { |post| SeriesTitle.parse(post.title)&.key == parsed.key }
    series ||= earlier.filter_map(&:series).first
    return if series.nil? && earlier.empty?

    Suggestion.new(series: series, title: series&.title || parsed.base, part: parsed.part,
                   post_ids: earlier.reject { |post| post.series_id.present? }.map(&:id))
  end

  # Runs of two or more parts by the same author sharing a base title, plus
  # single parts (a "(1)" with nothing after it yet) when singles: true.
  # An untitled breath counts by the first line of its words.
  def groups(scope = Post.all, singles: false, exclude_ids: [])
    candidates = scope.where(anonymous: false).where.not(id: exclude_ids)
                      .where(MAYBE_PART_SQL, hint: MARKER_HINT)
                      .includes(:user, :room, :rich_text_content).order(:created_at)
    parsed = candidates.to_h { |post| [ post, SeriesTitle.parse(SeriesTitle.effective_title(post)) ] }

    parsed.select { |_, info| info&.key }
          .group_by { |post, info| [ post.user_id, info.key ] }
          .filter_map do |(_, key), rows|
            next if rows.size < 2 && !singles

            ordered = rows.sort_by { |post, info| [ info.part.to_i, post.published_at || post.created_at, post.id ] }.map(&:first)
            Group.new(user: ordered.first.user, key: key, title: parsed[ordered.first].base, posts: ordered)
          end
          .sort_by { |group| [ group.user.username.to_s.downcase, group.key ] }
  end

  # Signed, titled breaths (an anonymous one can't join a named series).
  def candidate_posts(scope, exclude_post_id)
    scope = scope.where(anonymous: false).where.not(title: [ nil, "" ])
    scope = scope.where.not(id: exclude_post_id) if exclude_post_id
    scope.order(created_at: :desc)
  end
end
