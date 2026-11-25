# frozen_string_literal: true

module ContactPrivacyHelper
  # "Only me", "Connections I choose (3)", "All my connections", "Everyone".
  def contact_visibility_label(card, field)
    level = card.visibility_for(field)
    label = BrethrenCard::VISIBILITY_OPTIONS.fetch(level)[:label]
    return label unless level == "chosen"

    count = card.user.contact_shares.size
    "#{label} (#{count})"
  end
end
