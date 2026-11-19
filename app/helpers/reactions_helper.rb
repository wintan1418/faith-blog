# frozen_string_literal: true

module ReactionsHelper
  # Facebook / LinkedIn-style "who reacted" label for a hover tooltip.
  # Given the Like records for a single emoji (user preloaded), returns up to
  # `limit` usernames then "and N others". Pass `total` when `likes` is only
  # the first few of a larger group.
  REACTOR_TOOLTIP_LIMIT = 12

  def reactor_names_label(likes, limit: REACTOR_TOOLTIP_LIMIT, total: nil)
    names = likes.filter_map { |like| like.user&.username }
    return "" if names.empty?

    total = [ total.to_i, names.size ].max
    if total <= limit
      names.to_sentence
    else
      shown   = names.first(limit)
      hidden  = total - shown.size
      "#{shown.join(', ')} and #{hidden} #{'other'.pluralize(hidden)}"
    end
  end

  # [[emoji, count], ...] for a post, most-used first (ties: the emoji used
  # first). From the `reaction_tallies` GROUP BY, preloaded for feed cards.
  def reaction_counts_for(post)
    post.reaction_tallies.to_a
        .sort_by { |row| [ -row.tally.to_i, row.first_like_id.to_i ] }
        .map { |row| [ row.reaction_emoji, row.tally.to_i ] }
  end

  # The signed-in viewer's Like on a post, or nil. Uses the preloaded
  # `viewer_like` when it was loaded for this viewer.
  def my_reaction_to(post)
    return nil unless user_signed_in?
    return post.viewer_like if Current.user&.id == current_user.id

    current_user.likes.find_by(likeable: post)
  end

  # The first few reactors per emoji (for the tooltip), one small query each.
  def reactors_by_emoji(post, emojis, limit: REACTOR_TOOLTIP_LIMIT)
    emojis.index_with do |emoji|
      post.likes.where(reaction_emoji: emoji).includes(:user).order(:id).limit(limit).to_a
    end
  end
end
