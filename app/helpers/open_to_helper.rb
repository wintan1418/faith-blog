# frozen_string_literal: true

# "Open to" (work, hiring, mentoring...): a coloured ring around a member's
# photo and a small badge, shown only to the people they chose (everyone, or
# their connections).
module OpenToHelper
  # The "Open to" choices this viewer may see for this member, in ring order.
  def visible_open_to(user, viewer = (current_user if user_signed_in?))
    profile = user&.profile
    choices = profile&.open_to.to_a
    return [] if choices.empty?
    return choices if profile.open_to_shown_to_everyone? || viewer == user
    return [] unless viewer

    viewer_connection_ids.include?(user.id) ? choices : []
  end

  # "ot-ring ot-ring--green" for the avatar wrapper, or nil.
  def open_to_ring_class(user)
    first = visible_open_to(user).first
    "ot-ring ot-ring--#{Profile::OPEN_TO[first][:colour]}" if first
  end

  # The small pill under a photo ("Mentor", "Open to work").
  def open_to_badge(user, extra_class: nil)
    first = visible_open_to(user).first
    return unless first

    info = Profile::OPEN_TO[first]
    tag.span(info[:badge], class: [ "ot-badge", "ot-badge--#{info[:colour]}", extra_class ].compact.join(" "),
                           title: "Open to: #{visible_open_to(user).map { |key| Profile::OPEN_TO[key][:label].downcase }.to_sentence}")
  end

  # True when the signed-in member is connected to this one.
  def connected_viewer?(user) = user_signed_in? && viewer_connection_ids.include?(user.id)

  private

  # Once per request: the signed-in member's connections.
  def viewer_connection_ids
    @viewer_connection_ids ||= user_signed_in? ? current_user.connection_ids.to_set : Set.new
  end
end
