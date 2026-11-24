# frozen_string_literal: true

module SeriesHelper
  # [part number, last part number] of a breath among the parts everyone may
  # see, or nil. Numbers are the writer's own, so a gap stays a gap ("Part 6
  # of 6" when part 5 was never posted). One small query per series per
  # request, however many cards show it.
  def series_place(post)
    return unless post.series_id && post.series_position && post.series_listable?

    rows = series_public_parts(post.series_id)
    return unless rows.size > 1 && rows.any? { |id, _| id == post.id }

    [ post.series_position, series_last_number(rows.map(&:last)) ]
  end

  # "Part 2 of 3" for a feed card.
  def series_part_label(post)
    place = series_place(post)
    place && "Part #{place.first} of #{place.last}"
  end

  def series_last_number(numbers)
    numbers.compact.max.to_i
  end

  # A part's name in a list: its title, or the start of an untitled breath.
  def series_part_title(post, length: 90)
    post.display_title.presence ||
      truncate(post.content&.to_plain_text.to_s.squish, length: length, separator: " ").presence ||
      "Untitled breath"
  end

  # The parts of a breath's series this viewer may see, when it has more than
  # one and the breath itself is among them: [parts, index] or nil.
  def series_context_for(post, viewer)
    return unless post.series

    parts = post.series.parts_for(viewer)
    index = parts.index { |part| part.id == post.id }
    index && parts.size > 1 ? [ parts, index ] : nil
  end

  # Why the author sees a part other readers don't.
  def series_part_private_reason(post)
    return "Draft" if post.draft?
    return "Scheduled" if post.scheduled?
    return "Archived" if post.archived?
    return "Held for review" if post.held_for_review?
    return "Prayer request, not listed" if post.prayer?
    return "Private room, not listed" if post.room && !post.room.is_public?

    nil
  end

  # The signed-in member's series for the composer's picker (newest first).
  def composer_series_options
    return [] unless user_signed_in?

    @composer_series_options ||= current_user.series.order(created_at: :desc).to_a
  end

  private

  def series_public_parts(series_id)
    @series_public_parts ||= {}
    @series_public_parts[series_id] ||=
      Post.series_listable.where(series_id: series_id).order(:series_position, :published_at, :id)
          .pluck(:id, :series_position)
  end
end
