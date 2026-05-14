# frozen_string_literal: true

module ReactionsHelper
  # Facebook / LinkedIn-style "who reacted" label for a hover tooltip.
  # Given the Like records for a single emoji, returns up to `limit`
  # usernames then "and N others". Expects each like's user to be
  # preloaded (feed eager-loads `likes: :user`).
  REACTOR_TOOLTIP_LIMIT = 12

  def reactor_names_label(likes, limit: REACTOR_TOOLTIP_LIMIT)
    names = likes.filter_map { |like| like.user&.username }
    return "" if names.empty?

    if names.size <= limit
      names.to_sentence
    else
      shown   = names.first(limit)
      hidden  = names.size - limit
      "#{shown.join(', ')} and #{hidden} #{'other'.pluralize(hidden)}"
    end
  end
end
