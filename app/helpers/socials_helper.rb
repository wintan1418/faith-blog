# frozen_string_literal: true

# "Follow Brethreign" rows and plain, one-colour social icons (inline SVG,
# drawn in currentColor so they sit quietly in light and dark themes).
module SocialsHelper
  SOCIAL_ICON_PATHS = {
    "x" => '<path fill="currentColor" stroke="none" d="M17.75 3h3.07l-6.71 7.67L22 21h-6.18l-4.84-6.33L5.44 21H2.37l7.18-8.2L2 3h6.33l4.38 5.79zm-1.08 16.2h1.7L7.4 4.73H5.58z"/>',
    "instagram" => '<rect x="3.2" y="3.2" width="17.6" height="17.6" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.4" cy="6.6" r="1.1" fill="currentColor" stroke="none"/>',
    "linkedin" => '<rect x="3" y="3" width="18" height="18" rx="3.5"/><path d="M8 10.5v6.5"/><circle cx="8" cy="7.4" r="1.15" fill="currentColor" stroke="none"/><path d="M12 17v-6.5M12 13.4a2.6 2.6 0 0 1 5.2 0V17"/>',
    "substack" => '<path fill="currentColor" stroke="none" d="M4 3.5h16v2.3H4zM4 8.1h16v2.3H4zM4 12.7h16V21l-8-4.5L4 21z"/>',
    "email" => '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m3.8 6.6 8.2 6.3 8.2-6.3"/>',
    "facebook" => '<path d="M15.5 3.5h-2.2a3.8 3.8 0 0 0-3.8 3.8v13.2M7 10.5h7.5"/>',
    "youtube" => '<rect x="2.5" y="5.5" width="19" height="13" rx="4"/><path fill="currentColor" stroke="none" d="M10 9.2v5.6l4.8-2.8z"/>'
  }.freeze

  def social_icon(key, classes: "h-5 w-5")
    paths = SOCIAL_ICON_PATHS[key.to_s] || SOCIAL_ICON_PATHS["email"]
    tag.svg(paths.html_safe, viewBox: "0 0 24 24", class: classes, fill: "none", stroke: "currentColor",
            "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true",
            focusable: "false")
  end

  # Brethreign's accounts (config/socials.yml). `email: false` leaves the address out.
  def brand_social_accounts(email: true)
    email ? BrandSocials.all : BrandSocials.profiles
  end

  # A page's own accounts; the official Brethreign page falls back to ours.
  def page_social_accounts(page)
    accounts = page.socials.to_h.filter_map do |key, url|
      label = Page::SOCIAL_NETWORKS[key]
      BrandSocials::Account.new(key: key, label: label, handle: label, url: url) if label && url.present?
    end
    return accounts if accounts.any?
    return BrandSocials.all if page.handle.to_s.casecmp?(OfficialPage::HANDLE)

    []
  end

  # Opens outside Brethreign: a new tab on the web; the apps hand other
  # sites to the system browser (or the X / Instagram app).
  def social_link_options(account, classes:)
    opts = { class: classes, title: "#{account.label}: #{account.handle}", aria: { label: "#{account.label} (#{account.handle})" } }
    opts.merge!(target: "_blank", rel: "noopener me") unless account.email?
    opts
  end
end
