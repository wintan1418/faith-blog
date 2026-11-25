# frozen_string_literal: true

# Pages (churches, ministries, businesses…): logos, covers, chips and the
# "Post as" choices in the composer.
module OrgPagesHelper
  # The page's logo (a rounded square), or its initial on a tint.
  def page_logo(page, classes: "pg-logo", px: 96)
    if page.logo.attached?
      image_tag resized_image_src(page.logo, width: px, height: px, crop: "fill"), class: "#{classes} object-cover", alt: "", loading: "lazy"
    else
      tag.span(page.initial, class: "#{classes} pg-logo-fallback", style: avatar_tint_style(page.handle.to_s), aria: { hidden: true })
    end
  end

  def page_cover_src(page, width: 1500)
    resized_image_src(page.cover, width: width, height: (width / 3.0).round, crop: "fill", gravity: "auto")
  end

  def page_verified_badge(page, classes: "h-4 w-4")
    return unless page.verified?

    tag.span(render_icon("badgecheck", classes: classes), class: "eg-verified pg-verified", role: "img", aria: { label: "Verified page" },
                                                          title: "Verified page")
  end

  # "Church · Akure, Nigeria"
  def page_subline(page)
    [ page.category_label, page.short_place.presence ].compact.join(" · ")
  end

  def page_followers_label(page)
    n = page.followers_count.to_i
    "#{number_with_delimiter(n)} #{n == 1 ? 'follower' : 'followers'}"
  end

  def page_category_options
    Page::CATEGORIES.map { |key, info| [ info[:label], key ] }
  end

  # Where "Contact" goes: the page's email, else its website, else nothing.
  def page_contact_href(page)
    return "mailto:#{page.email}" if page.email.present?

    page.website.presence
  end
end
