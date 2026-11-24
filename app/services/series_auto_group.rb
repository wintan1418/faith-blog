# frozen_string_literal: true

# When a writer publishes a breath whose title is clearly the next part of
# their own earlier writing ("Who Is a Teenager? (7)", "(5/7)" style markers
# after the same base title, "Part 5", "Day 5"), it joins that series on its
# own; if the earlier part isn't in a series yet, one is made with both. The
# composer then shows "Added to … as Part 5 · Undo".
#
# Only ever the same author's breaths, never anonymous ones, and never when
# the writer already picked a series themselves.
module SeriesAutoGroup
  Result = Data.define(:series, :created, :number)

  module_function

  def call(post)
    return unless post.persisted? && post.published? && post.series_id.nil? && !post.anonymous? && post.user
    parsed = SeriesTitle.parse(SeriesTitle.effective_title(post))
    return unless parsed&.key && parsed.part

    user = post.user
    series = user.series.find { |s| SeriesTitle.key_for(s.title) == parsed.key }
    earlier = []
    if series.nil?
      matching = user.posts.named.where.not(id: post.id).where.not(title: [ nil, "" ]).includes(:series)
                     .order(created_at: :desc).limit(SeriesSuggestions::LOOKBACK)
                     .select { |p| SeriesTitle.parse(p.title)&.key == parsed.key }
      series = matching.filter_map(&:series).find { |s| s.user_id == user.id }
      earlier = matching.reject(&:series_id) if series.nil?
      return if series.nil? && earlier.empty?
    end

    created = series.nil?
    Series.transaction do
      if created
        first = earlier.min_by { |p| [ SeriesTitle.parse(p.title).part.to_i, p.created_at ] }
        series = user.series.create!(title: SeriesTitle.parse(first.title).base)
        ordered = (earlier + [ post ]).sort_by do |p|
          [ SeriesTitle.parse(SeriesTitle.effective_title(p))&.part || Float::INFINITY, p.published_at || p.created_at ]
        end
        series.number_parts!(ordered)
      else
        number = series.next_position(title: SeriesTitle.effective_title(post))
        post.update_columns(series_id: series.id, series_position: number)
      end
    end
    post.reload
    # Columns were written directly, so tell followers here (after the undo window).
    SeriesPartAlertJob.set(wait: SeriesPartAlertJob::DELAY).perform_later(post.id) unless created
    Result.new(series: series, created: created, number: post.series_position)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[SeriesAutoGroup] post #{post.id}: #{e.message}")
    nil
  end
end
