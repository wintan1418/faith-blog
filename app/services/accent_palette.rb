# frozen_string_literal: true

# Curated accent colours each user can pick from. Every entry is paired with
# a darker shade (used for hover / icon-tint) so contrast is always sound.
# To add a new colour: append to PALETTE — no migration needed because the
# users.accent_color column stores the slug string.
module AccentPalette
  PALETTE = {
    "mint"    => { name: "Mint",    accent: "#34d399", accent_2: "#10b981", accent_soft: "rgba(52, 211, 153, 0.16)" },
    "forest"  => { name: "Forest",  accent: "#16a34a", accent_2: "#15803d", accent_soft: "rgba(22, 163, 74, 0.16)" },
    "teal"    => { name: "Teal",    accent: "#2dd4bf", accent_2: "#0d9488", accent_soft: "rgba(45, 212, 191, 0.16)" },
    "cyan"    => { name: "Cyan",    accent: "#22d3ee", accent_2: "#0891b2", accent_soft: "rgba(34, 211, 238, 0.16)" },
    "sky"     => { name: "Sky",     accent: "#38bdf8", accent_2: "#0284c7", accent_soft: "rgba(56, 189, 248, 0.16)" },
    "ocean"   => { name: "Ocean",   accent: "#06b6d4", accent_2: "#0e7490", accent_soft: "rgba(6, 182, 212, 0.16)" },
    "indigo"  => { name: "Indigo",  accent: "#818cf8", accent_2: "#4f46e5", accent_soft: "rgba(129, 140, 248, 0.16)" },
    "violet"  => { name: "Violet",  accent: "#c084fc", accent_2: "#9333ea", accent_soft: "rgba(192, 132, 252, 0.16)" },
    "magenta" => { name: "Magenta", accent: "#ec4899", accent_2: "#be185d", accent_soft: "rgba(236, 72, 153, 0.16)" },
    "rose"    => { name: "Rose",    accent: "#fb7185", accent_2: "#e11d48", accent_soft: "rgba(251, 113, 133, 0.16)" },
    "crimson" => { name: "Crimson", accent: "#ef4444", accent_2: "#b91c1c", accent_soft: "rgba(239, 68, 68, 0.16)" },
    "fire"    => { name: "Fire",    accent: "#f97316", accent_2: "#c2410c", accent_soft: "rgba(249, 115, 22, 0.16)" },
    "coral"   => { name: "Coral",   accent: "#fb923c", accent_2: "#ea580c", accent_soft: "rgba(251, 146, 60, 0.16)" },
    "amber"   => { name: "Amber",   accent: "#fbbf24", accent_2: "#d97706", accent_soft: "rgba(251, 191, 36, 0.16)" },
    "gold"    => { name: "Gold",    accent: "#d4a85a", accent_2: "#a8801f", accent_soft: "rgba(212, 168, 90, 0.18)" },
    "lime"    => { name: "Lime",    accent: "#84cc16", accent_2: "#4d7c0f", accent_soft: "rgba(132, 204, 22, 0.16)" },
    "slate"   => { name: "Slate",   accent: "#94a3b8", accent_2: "#475569", accent_soft: "rgba(148, 163, 184, 0.16)" }
  }.freeze

  DEFAULT = "mint"

  def self.slugs
    PALETTE.keys
  end

  def self.valid?(slug)
    PALETTE.key?(slug.to_s)
  end

  def self.for(slug)
    PALETTE[slug.to_s] || PALETTE[DEFAULT]
  end

  # Inline-style snippet for the <body> tag so every .fc-accent var cascades
  # from the user's pick. Returns "" for users who haven't picked (use the
  # baseline stylesheet defaults).
  def self.css_vars(slug)
    return "" if slug.blank? || slug == DEFAULT
    swatch = self.for(slug)
    rgb = hex_to_rgb(swatch[:accent])
    glow = "rgba(#{rgb.join(', ')}, 0.45)"
    [
      "--fc-accent: #{swatch[:accent]}",
      "--fc-accent-2: #{swatch[:accent_2]}",
      "--fc-accent-deep: #{swatch[:accent_2]}",
      "--fc-accent-soft: #{swatch[:accent_soft]}",
      "--fc-accent-glow: #{glow}"
    ].join("; ") + ";"
  end

  def self.hex_to_rgb(hex)
    h = hex.to_s.delete_prefix("#")
    [ h[0..1], h[2..3], h[4..5] ].map { |c| c.to_i(16) }
  end
end
