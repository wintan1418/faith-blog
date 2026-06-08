# frozen_string_literal: true

module ApplicationHelper
  include Pagy::Frontend

  def page_title(title = nil)
    base_title = "Faith Community"
    title.present? ? "#{title} - #{base_title}" : base_title
  end

  # Deterministic muted background + readable foreground for avatar fallbacks
  # without a photo. Same username → same hue every time. Sets CSS vars
  # (rather than background directly) because the base .fc-avatar rule uses
  # !important to lock the mint default — the !important rule reads these
  # vars so per-user inline values win.
  def avatar_tint_style(seed)
    return "" if seed.blank?
    hue = seed.to_s.bytes.sum % 360
    "--fc-avatar-bg: hsl(#{hue} 42% 72%); --fc-avatar-fg: hsl(#{hue} 55% 18%);"
  end

  # Whether the signed-in user has joined a post's prayer chain. The set of
  # post ids the user interceded on is loaded once per request and memoized, so
  # rendering a feed of prayer cards is a single query instead of one per card.
  def joined_prayer_chain?(post)
    return false unless user_signed_in?

    @joined_prayer_post_ids ||= current_user.prayer_intercessions.pluck(:post_id).to_set
    @joined_prayer_post_ids.include?(post.id)
  end

  def preview_for(reviewable)
    case reviewable
    when Post
      [ reviewable.title, reviewable.content.to_plain_text ].compact.join(" — ")
    when Comment
      reviewable.content.to_plain_text
    else
      reviewable.try(:body).to_s
    end
  end

  def safe_external_url(url)
    uri = URI.parse(url.to_s)
    return url if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    "#"
  rescue URI::InvalidURIError
    "#"
  end

  def avatar_for(user, size: :medium)
    sizes = {
      small: "w-8 h-8",
      medium: "w-10 h-10",
      large: "w-16 h-16",
      xlarge: "w-24 h-24"
    }

    css_class = "#{sizes[size]} rounded-full object-cover"

    if user.profile.avatar.attached?
      variant = case size
      when :small then user.profile.avatar_thumbnail
      when :large, :xlarge then user.profile.avatar_large
      else user.profile.avatar_medium
      end
      image_tag variant, class: css_class
    else
      content_tag :div, class: "#{sizes[size]} rounded-full bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center text-white font-medium" do
        user.username[0].upcase
      end
    end
  end

  def time_ago_short(time)
    return "" unless time

    seconds = (Time.current - time).to_i

    case seconds
    when 0..59 then "#{seconds}s"
    when 60..3599 then "#{seconds / 60}m"
    when 3600..86399 then "#{seconds / 3600}h"
    when 86400..604799 then "#{seconds / 86400}d"
    when 604800..2419199 then "#{seconds / 604800}w"
    else time.strftime("%b %d")
    end
  end

  def pagy_nav(pagy)
    return "" if pagy.pages <= 1

    html = '<nav class="flex items-center justify-center gap-1" aria-label="Pagination">'

    if pagy.prev
      html += link_to(pagy_url_for(pagy, pagy.prev), class: "px-3 py-2 rounded-lg text-sm font-medium text-stone-600 hover:bg-stone-100 transition-colors") do
        '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>'.html_safe
      end
    end

    pagy.series.each do |item|
      case item
      when Integer
        html += link_to(item.to_s, pagy_url_for(pagy, item), class: "px-3 py-2 rounded-lg text-sm font-medium #{item == pagy.page ? 'bg-amber-100 text-amber-800' : 'text-stone-600 hover:bg-stone-100'} transition-colors")
      when String
        html += content_tag(:span, item, class: "px-3 py-2 rounded-lg text-sm font-medium bg-amber-100 text-amber-800")
      when :gap
        html += content_tag(:span, "...", class: "px-2 py-2 text-stone-400")
      end
    end

    if pagy.next
      html += link_to(pagy_url_for(pagy, pagy.next), class: "px-3 py-2 rounded-lg text-sm font-medium text-stone-600 hover:bg-stone-100 transition-colors") do
        '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>'.html_safe
      end
    end

    html += "</nav>"
    html.html_safe
  end
end
