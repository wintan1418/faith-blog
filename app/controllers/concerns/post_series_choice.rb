# frozen_string_literal: true

# The composer's "Part of a series" control (posts#create / posts#update).
#
#   post[series_id]             "" = not in a series, "new" = make one, or an id
#   post[new_series_title]      the new series' name
#   post[series_adopt_post_ids] earlier parts to bring along (from the
#                               "looks like part 4 of …" hint)
#
# Only the author's own series and breaths are ever touched. A form without
# the series_id field leaves the breath's series as it was.
module PostSeriesChoice
  extend ActiveSupport::Concern

  private

  # Sets post.series from the form. Returns an error message, or nil.
  def assign_series_choice(post)
    @series_choice_new = false
    @series_adopt_ids = []
    choice = nested_param(:post, :series_id)
    # Staff can edit a breath, but only its author files it in a series.
    return if choice.nil? || (post.user_id.present? && post.user_id != current_user.id)

    case choice.to_s
    when ""
      post.series = nil
    when "new"
      title = nested_param(:post, :new_series_title).to_s.squish
      return "Give your new series a name." if title.blank?

      series = existing_series_named(title) || current_user.series.build(title: title)
      return series.errors.full_messages.to_sentence unless series.persisted? || series.valid?

      @series_choice_new = series.new_record?
      post.series = series
    else
      series = current_user.series.find_by(id: choice)
      return "That series isn't one of yours." unless series

      post.series = series unless post.series_id == series.id
    end
    @series_adopt_ids = Array(nested_param(:post, :series_adopt_post_ids)).flat_map { |v| v.to_s.split(",") }
                                                                         .map(&:to_i).select(&:positive?)
    nil
  end

  # Runs after the post saved: bring earlier parts along and, for a series
  # made just now, put the parts in their numbered order.
  def finish_series_choice(post)
    series = post.series
    return unless series

    adopted = current_user.posts.where(id: @series_adopt_ids, series_id: nil, anonymous: false)
                          .where.not(id: post.id).select { |part| part.update(series: series) }
    order_by_part_numbers(series) if @series_choice_new || adopted.any?
  end

  # A just-published breath that is clearly the next part of the writer's own
  # earlier writing joins (or starts) that series on its own; the post page
  # then offers "Undo" (posts/_series_auto_notice).
  def auto_group_into_series(post)
    return unless post.series_id.nil?

    result = SeriesAutoGroup.call(post)
    return unless result

    flash[:series_auto] = { "post_id" => post.id, "series" => result.series.slug, "title" => result.series.title,
                            "number" => result.number, "created" => result.created }
  end

  def existing_series_named(title)
    key = SeriesTitle.key_for(title)
    current_user.series.find { |s| SeriesTitle.key_for(s.title) == key }
  end

  # Parts in the order they were posted, numbered by the numbers in their
  # titles where they have them (gaps kept), counting on where they don't.
  def order_by_part_numbers(series)
    ordered = series.posts.reorder(nil).includes(:rich_text_content).to_a
                    .sort_by { |part| [ part.published_at || part.created_at, part.id ] }
    series.number_parts!(ordered)
  end
end
