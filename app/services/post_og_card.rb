# frozen_string_literal: true

# The link-preview image (og:image, 1200x630 JPEG) for a breath without a
# photo, so a link pasted into WhatsApp, LinkedIn or X shows a designed card:
# the title (or the opening words), the author, the counts and the Brethreign
# mark, in the author's accent colour.
#
# Drawn with libvips: Pango for the text (Inter, shipped in vendor/fonts so
# every server draws the same letters), gradients and pills computed in vips,
# and the few icons stamped from PNG masks in vendor/og (Active Storage blocks
# vips' SVG loader in the app, on purpose; script/render_og_masks.rb makes
# them).
#
# Cached as the breath's `og_card` attachment. The page links it with a
# version in the address, so crawlers get a new card when the words, author
# or look change, and when the counts change, at most once a day.
#
# Never shows anything the breath page wouldn't show a stranger: only public
# breaths get one, and an anonymous breath shows "Anonymous", no avatar and
# the house colour.
class PostOgCard
  WIDTH = 1200
  HEIGHT = 630
  PAD = 72
  AVATAR = 76
  DESIGN = "1"
  COUNTS_TTL = 1.day
  FONT_FILE = Rails.root.join("vendor/fonts/Inter.ttf").to_s
  FONT = "Inter"
  MASKS = Rails.root.join("vendor/og")
  INK = "#0d1f18"
  MUTED = "#5b6b64"
  ON_ACCENT = "#06281c"
  EMOJI = /\p{Extended_Pictographic}|[\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}]/
  MATH_ALPHANUMERIC = /[\u{1D400}-\u{1D7FF}]/

  def initialize(post)
    @post = post
  end

  # What the page puts in the image address: the stored card's version while
  # it is still good, otherwise the version a fresh card will have.
  def version
    fresh?(stored_meta) ? stored_meta["og_version"] : current_version
  end

  # The JPEG bytes, drawing and storing a new card when the stored one is stale.
  def jpeg
    if fresh?(stored_meta)
      data = download_stored
      return data if data
    end

    data = render
    store(data)
    data
  end

  def render
    @layers = []
    canvas = background
    draw_header
    draw_words
    draw_footer
    images = @layers.map(&:first)
    canvas = canvas.composite(images, :over, x: @layers.map { _1[1] }, y: @layers.map { _1[2] }, compositing_space: :srgb)
    canvas.flatten(background: [ 255, 255, 255 ]).cast(:uchar).copy(interpretation: :srgb)
          .jpegsave_buffer(Q: 88, strip: true, optimize_coding: true)
  end

  def current_version = "#{content_key}#{counts_key}"

  private

  attr_reader :post

  def palette = @palette ||= AccentPalette.for(post.anonymous? ? nil : post.user&.accent_color)

  def author = post.anonymous? ? nil : post.user

  # ── Versioning ──────────────────────────────────────────────────────

  def content_key
    @content_key ||= Digest::SHA256.hexdigest([
      DESIGN, post.title.to_s, body_text.first(600), post.anonymous?, author&.username, author&.verified_at.present?,
      palette[:accent], avatar_blob&.id, label
    ].join("\u0001")).first(10)
  end

  def counts_key = "-#{post.likes_count.to_i}.#{post.comments_count.to_i}"

  def stored_meta
    @stored_meta ||= post.og_card.attached? ? post.og_card.blob.metadata.to_h : {}
  rescue StandardError
    @stored_meta = {}
  end

  def fresh?(meta)
    return false if meta.blank? || meta["og_version"].blank?
    return false unless meta["og_version"].start_with?(content_key)
    return true if meta["og_version"] == current_version

    generated = Time.zone.parse(meta["generated_at"].to_s)
    generated.present? && generated > COUNTS_TTL.ago
  rescue ArgumentError
    false
  end

  def download_stored
    post.og_card.download
  rescue StandardError => e
    Rails.logger.warn("[PostOgCard] stored card unreadable for post #{post.id}: #{e.class}: #{e.message}")
    nil
  end

  # Attached without saving the post (no callbacks, no updated_at bump); any
  # older card is purged in the background.
  def store(data)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data), filename: "breath-#{post.id}-card.jpg", content_type: "image/jpeg", identify: false,
      metadata: { "og_version" => current_version, "generated_at" => Time.current.iso8601,
                  "width" => WIDTH, "height" => HEIGHT, "analyzed" => true, "identified" => true }
    )
    attachment = ActiveStorage::Attachment.create!(name: "og_card", record: post, blob: blob)
    ActiveStorage::Attachment.where(record: post, name: "og_card").where.not(id: attachment.id).find_each(&:purge_later)
    post.association(:og_card_attachment).reset
    @stored_meta = nil
  rescue StandardError => e
    Rails.logger.warn("[PostOgCard] could not store card for post #{post.id}: #{e.class}: #{e.message}")
  end

  # ── Words ───────────────────────────────────────────────────────────

  def body_text
    @body_text ||= clean(post.content&.to_plain_text.to_s)
  end

  def title_text = clean(post.title.to_s)

  def label
    return "Answered prayer" if post.prayer_status_prayer_answered?
    return "Prayer request" if post.prayer_status_prayer_pending?

    "A breath"
  end

  def date = (post.published_at || post.created_at).strftime("%b %-d, %Y")

  # Styled letters (𝗪𝗵𝗼) become plain ones (the card sets its own weight)
  # and emoji go: a server's fonts can't be trusted to draw them.
  def clean(text)
    text.gsub(MATH_ALPHANUMERIC) { |c| c.unicode_normalize(:nfkc) }.gsub(EMOJI, "").gsub(/\s+/, " ").strip
  end

  def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  def text_image(text, size:, weight: "Regular", color: INK, width: nil)
    markup = %(<span foreground="#{color}">#{escape(text)}</span>)
    options = { font: "#{FONT} #{weight} #{size}", fontfile: FONT_FILE, rgba: true, dpi: 72 }
    if width
      options[:width] = width
      options[:spacing] = (size * 0.24).round
    end
    Vips::Image.text(markup, **options)
  end

  # The biggest size that fits; at the smallest, as many words as fit, then "…".
  def fit(text, sizes:, width:, max_height:, weight:, color: INK)
    return if text.blank?

    sizes.each do |size|
      image = text_image(text, size: size, weight: weight, color: color, width: width)
      return image if image.height <= max_height
    end
    words = text.split
    low = 1
    high = words.size
    best = nil
    while low <= high
      mid = (low + high) / 2
      clipped = "#{words.first(mid).join(' ').sub(/[[:punct:]]+\z/, '')}…"
      candidate = text_image(clipped, size: sizes.last, weight: weight, color: color, width: width)
      if candidate.height <= max_height
        best = candidate
        low = mid + 1
      else
        high = mid - 1
      end
    end
    best
  end

  def count(n)
    n = n.to_i
    return n.to_s if n < 1000

    n < 10_000 ? format("%.1fk", n / 1000.0).sub(".0k", "k") : "#{n / 1000}k"
  end

  # ── Drawing ─────────────────────────────────────────────────────────

  def place(image, x, y)
    @layers << [ image, x.round, y.round ] if image
  end

  def rgb(hex) = AccentPalette.hex_to_rgb(hex)

  # Linen, with a soft glow of the author's colour from the top right.
  def background
    xyz = Vips::Image.xyz(WIDTH, HEIGHT)
    x = xyz.extract_band(0)
    y = xyz.extract_band(1)
    light = rgb("#fbfaf6")
    dark = rgb("#efede4")
    t = (x + y) / (WIDTH + HEIGHT).to_f
    base = t * dark.zip(light).map { |d, l| d - l } + light
    base = glow(base, x, y, cx: WIDTH, cy: 0, radius: 820.0, color: palette[:accent], strength: 0.30)
    base = glow(base, x, y, cx: 0, cy: HEIGHT, radius: 640.0, color: palette[:accent_2], strength: 0.10)
    base = base.draw_rect(rgb(palette[:accent]), 0, 0, 12, HEIGHT, fill: true)
    divider = HEIGHT - PAD - AVATAR - 28
    base.draw_rect(rgb("#dedcd2"), PAD, divider, WIDTH - PAD * 2, 2, fill: true).bandjoin(255).copy(interpretation: :srgb)
  end

  def glow(base, x, y, cx:, cy:, radius:, color:, strength:)
    distance = (((x - cx)**2) + ((y - cy)**2))**0.5 / radius
    alpha = (distance < 1).ifthenelse((distance * -1) + 1, 0)
    alpha = (alpha * alpha) * strength
    (base * ((alpha * -1) + 1)) + (alpha * rgb(color))
  end

  # Grayscale mask → solid colour with that alpha.
  def tint(mask, hex, opacity = 1.0)
    colour = mask.new_from_image(rgb(hex)).cast(:uchar)
    colour.bandjoin((mask * opacity).cast(:uchar)).copy(interpretation: :srgb)
  end

  def mask(name) = Vips::Image.new_from_file(MASKS.join("#{name}.png").to_s).extract_band(0)

  # An anti-aliased pill (or circle, when w == h).
  def pill(w, h)
    r = h / 2.0
    xyz = Vips::Image.xyz(w, h)
    x = xyz.extract_band(0) + 0.5
    y = xyz.extract_band(1) + 0.5
    cx = (x < r).ifthenelse(r, (x > w - r).ifthenelse(w - r, x))
    coverage = (((x - cx)**2) + ((y - r)**2))**0.5 * -1 + (r + 0.5)
    coverage = (coverage < 0).ifthenelse(0, coverage)
    (coverage > 1).ifthenelse(1, coverage) * 255
  end

  def draw_header
    place(tint(mask("logomark"), palette[:accent_2]), PAD, PAD)
    place(text_image("Brethreign", size: 30, weight: "Bold"), PAD + 44, PAD + 6)

    tag = text_image(label.upcase, size: 17, weight: "Bold", color: palette[:accent_2])
    w = tag.width + 36
    x = WIDTH - PAD - w
    place(tint(pill(w, 40), palette[:accent], 0.18), x, PAD + 4)
    place(tag, x + 18, PAD + 4 + (40 - tag.height) / 2.0)
  end

  def draw_words
    inner = WIDTH - PAD * 2
    top = PAD + 86
    room = HEIGHT - PAD - AVATAR - 28 - 30 - top

    blocks = []
    if title_text.present?
      title = fit(title_text, sizes: [ 70, 64, 58, 52, 46, 42 ], width: inner, max_height: (room * 0.72).floor, weight: "Bold")
      blocks << title
      rest = room - (title ? title.height + 18 : 0)
      if rest > 36 && body_text.present?
        blocks << fit(body_text, sizes: [ 30, 28 ], width: inner, max_height: [ rest, 118 ].min, weight: "Regular", color: MUTED)
      end
    else
      blocks << fit("“#{body_text}”", sizes: [ 58, 52, 48, 44, 40, 36 ], width: inner, max_height: room, weight: "SemiBold")
    end
    blocks.compact!
    total = blocks.sum(&:height) + 18 * (blocks.size - 1)
    y = top + [ (room - total) * 0.42, 0 ].max
    blocks.each do |block|
      place(block, PAD, y)
      y += block.height + 18
    end
  end

  def draw_footer
    y = HEIGHT - PAD - AVATAR
    draw_avatar(y)
    name_x = PAD + AVATAR + 20
    name = text_image(author ? author.display_name : "Anonymous", size: 30, weight: "Bold")
    place(name, name_x, y + 6)
    place(tint(mask("verified"), palette[:accent_2]), name_x + name.width + 10, y + 7) if author&.verified_at.present?
    place(text_image(author ? "@#{author.username} · #{date}" : date, size: 23, color: MUTED), name_x, y + 46)

    cta = text_image("Join the conversation", size: 22, weight: "Bold", color: ON_ACCENT)
    pill_w = cta.width + 56
    pill_x = WIDTH - PAD - pill_w
    pill_y = HEIGHT - PAD - 58
    place(tint(pill(pill_w, 56), palette[:accent]), pill_x, pill_y)
    place(cta, pill_x + 28, pill_y + (56 - cta.height) / 2.0)

    right = pill_x - 30
    [ [ "bubble", post.comments_count ], [ "heart", post.likes_count ] ].each do |icon, n|
      number = text_image(count(n), size: 24, weight: "SemiBold", color: MUTED)
      right -= number.width
      place(number, right, pill_y + (56 - number.height) / 2.0)
      right -= 36
      place(tint(mask(icon), MUTED), right, pill_y + 14)
      right -= 22
    end
  end

  def draw_avatar(y)
    circle = pill(AVATAR, AVATAR)
    if author.nil?
      place(tint(circle, INK, 0.08), PAD, y)
      place(tint(mask("person"), MUTED), PAD + (AVATAR - 40) / 2, y + (AVATAR - 40) / 2)
    elsif (photo = avatar_photo)
      place(photo.bandjoin(circle.cast(:uchar)).copy(interpretation: :srgb), PAD, y)
    else
      place(tint(circle, palette[:accent]), PAD, y)
      initial = text_image(author.username.first.upcase, size: 34, weight: "Bold", color: ON_ACCENT)
      place(initial, PAD + (AVATAR - initial.width) / 2.0, y + (AVATAR - initial.height) / 2.0)
    end
  end

  def avatar_blob
    return unless author

    avatar = author.profile&.avatar
    avatar.blob if avatar&.attached?
  end

  def avatar_photo
    blob = avatar_blob
    return unless blob&.image?

    photo = Vips::Image.thumbnail_buffer(blob.download, AVATAR, height: AVATAR, crop: :attention)
    photo = photo.flatten(background: [ 255, 255, 255 ]) if photo.has_alpha?
    photo = photo.colourspace(:srgb)
    photo = photo.bandjoin([ photo, photo ]) if photo.bands == 1
    photo.cast(:uchar)
  rescue StandardError => e
    Rails.logger.warn("[PostOgCard] avatar failed for post #{post.id}: #{e.class}: #{e.message}")
    nil
  end
end
