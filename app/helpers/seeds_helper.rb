# frozen_string_literal: true

module SeedsHelper
  # A small rank chip: icon + name, tinted per rank. `compact` shows the icon
  # alone (for the dense spots, like beside a commenter's name).
  def seed_rank_chip(user_or_rank, compact: false, extra_class: nil)
    rank = user_or_rank.is_a?(Seeds::Rank) ? user_or_rank : user_or_rank&.seeds_rank
    return "".html_safe unless rank

    tag.span(class: [ "seed-rank", "seed-rank--#{rank.key}", ("is-compact" if compact), extra_class ].compact.join(" "),
             title: "#{rank.name} · Seeds rank", aria: { label: "Rank: #{rank.name}" }) do
      safe_join([ render_icon(rank.icon, classes: "seed-rank-ico"), (tag.span(rank.name, class: "seed-rank-name") unless compact) ].compact)
    end
  end

  def seeds_count(n) = "#{number_with_delimiter(n.to_i)} #{n.to_i == 1 ? 'seed' : 'seeds'}"
end
