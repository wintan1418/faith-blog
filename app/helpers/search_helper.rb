# frozen_string_literal: true

module SearchHelper
  # A one-line preview of a breath: its title, else the start of its text.
  def search_breath_label(post, length: 90)
    text = post.title.presence || post.content&.to_plain_text.to_s
    truncate(text.squish, length: length, omission: "…")
  end

  # Who to show as a breath's author in results. Anonymous breaths never
  # show (or link to) their author, whoever is searching.
  def search_breath_author(post)
    post.anonymous? ? nil : post.user
  end

  def search_avatar(user, size: "h-9 w-9", text: "text-sm")
    profile = user&.profile
    if profile&.avatar&.attached?
      image_tag avatar_src(profile, 96), alt: "", class: "srch-avatar #{size} object-cover", loading: "lazy"
    else
      tag.span((user&.username || "?").first.upcase, class: "srch-avatar srch-avatar-fallback #{size} #{text}", aria: { hidden: true })
    end
  end

  def search_tab_link(tab, label, current)
    active = tab == current
    link_to label, search_path(search_params(tab: (tab == "top" ? nil : tab), page: nil)),
            class: "srch-tab #{'is-active' if active}", aria: { current: (active ? "page" : nil) },
            data: { turbo_action: "advance" }
  end

  def search_kind_badges(post)
    badges = []
    badges << [ "image", "Photo" ] if post.images.attachments.any?
    badges << [ "mic", "Voice note" ] if post.voice_note.attached?
    badges
  end

  def search_result_count(result)
    return "No breaths" if result.total.zero?
    return "#{number_with_delimiter(result.total)}+ breaths" if result.capped?

    pluralize(number_with_delimiter(result.total), "breath")
  end
end
