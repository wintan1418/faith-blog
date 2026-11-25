# frozen_string_literal: true

# The link-preview image (og:image, 1200x630 JPEG) for a page: the page's
# name, tagline, logo, category and place, follower count, and the Brethreign
# mark. Same drawing kit, caching and versioning as PostOgCard; stored as the
# page's `og_card`. Only active pages get one.
class PageOgCard < PostOgCard
  LOGO = 96

  def initialize(page)
    @page = page
    super(nil)
  end

  def current_version = "#{content_key}#{counts_key}"

  private

  attr_reader :page

  def palette = @palette ||= AccentPalette.for(nil)

  def content_key
    @content_key ||= Digest::SHA256.hexdigest([
      DESIGN, page.name, page.tagline.to_s, page.handle, page.verified?, page.category, page.short_place.to_s,
      logo_blob&.id
    ].join("\u0001")).first(10)
  end

  def counts_key = "-#{page.followers_count.to_i}"

  def stored_meta
    @stored_meta ||= page.og_card.attached? ? page.og_card.blob.metadata.to_h : {}
  rescue StandardError
    @stored_meta = {}
  end

  def download_stored
    page.og_card.download
  rescue StandardError => e
    Rails.logger.warn("[PageOgCard] stored card unreadable for page #{page.id}: #{e.class}: #{e.message}")
    nil
  end

  def store(data)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data), filename: "page-#{page.id}-card.jpg", content_type: "image/jpeg", identify: false,
      metadata: { "og_version" => current_version, "generated_at" => Time.current.iso8601,
                  "width" => WIDTH, "height" => HEIGHT, "analyzed" => true, "identified" => true }
    )
    attachment = ActiveStorage::Attachment.create!(name: "og_card", record: page, blob: blob)
    ActiveStorage::Attachment.where(record: page, name: "og_card").where.not(id: attachment.id).find_each(&:purge_later)
    page.association(:og_card_attachment).reset
    @stored_meta = nil
  rescue StandardError => e
    Rails.logger.warn("[PageOgCard] could not store card for page #{page.id}: #{e.class}: #{e.message}")
  end

  def label = page.category_label

  def draw_words
    inner = WIDTH - PAD * 2
    top = PAD + 96
    room = HEIGHT - PAD - LOGO - 28 - 30 - top
    blocks = []
    title = fit(clean(page.name), sizes: [ 76, 68, 60, 52, 46 ], width: inner, max_height: (room * 0.62).floor, weight: "Bold")
    blocks << title
    tagline = clean(page.tagline.to_s.presence || page.about.to_s.squish)
    rest = room - (title ? title.height + 18 : 0)
    blocks << fit(tagline, sizes: [ 32, 30, 28 ], width: inner, max_height: [ rest, 124 ].min, weight: "Regular", color: MUTED) if rest > 36 && tagline.present?
    blocks.compact!
    total = blocks.sum(&:height) + 18 * (blocks.size - 1)
    y = top + [ (room - total) * 0.42, 0 ].max
    blocks.each do |block|
      place(block, PAD, y)
      y += block.height + 18
    end
  end

  def draw_footer
    y = HEIGHT - PAD - LOGO
    draw_logo(y)
    name_x = PAD + LOGO + 22
    handle = text_image("@#{page.handle}", size: 30, weight: "Bold")
    place(handle, name_x, y + 10)
    place(tint(mask("verified"), palette[:accent_2]), name_x + handle.width + 10, y + 11) if page.verified?
    sub = [ page.category_label, page.short_place.presence, "#{count(page.followers_count)} #{page.followers_count == 1 ? 'follower' : 'followers'}" ].compact.join(" · ")
    place(text_image(clean(sub), size: 23, color: MUTED), name_x, y + 52)

    cta = text_image("Follow on Brethreign", size: 22, weight: "Bold", color: ON_ACCENT)
    pill_w = cta.width + 56
    pill_x = WIDTH - PAD - pill_w
    pill_y = HEIGHT - PAD - 58
    place(tint(pill(pill_w, 56), palette[:accent]), pill_x, pill_y)
    place(cta, pill_x + 28, pill_y + (56 - cta.height) / 2.0)
  end

  def draw_logo(y)
    if (photo = logo_photo)
      place(photo.bandjoin(rounded_square(LOGO).cast(:uchar)).copy(interpretation: :srgb), PAD, y)
    else
      place(tint(rounded_square(LOGO), palette[:accent]), PAD, y)
      initial = text_image(page.initial, size: 44, weight: "Bold", color: ON_ACCENT)
      place(initial, PAD + (LOGO - initial.width) / 2.0, y + (LOGO - initial.height) / 2.0)
    end
  end

  # An anti-aliased square with 22% rounded corners (a logo tile).
  def rounded_square(size)
    r = size * 0.22
    xyz = Vips::Image.xyz(size, size)
    x = xyz.extract_band(0) + 0.5
    y = xyz.extract_band(1) + 0.5
    cx = (x < r).ifthenelse(r, (x > size - r).ifthenelse(size - r, x))
    cy = (y < r).ifthenelse(r, (y > size - r).ifthenelse(size - r, y))
    coverage = (((x - cx)**2) + ((y - cy)**2))**0.5 * -1 + (r + 0.5)
    coverage = (coverage < 0).ifthenelse(0, coverage)
    (coverage > 1).ifthenelse(1, coverage) * 255
  end

  def logo_blob
    page.logo.blob if page.logo.attached?
  end

  def logo_photo
    blob = logo_blob
    return unless blob&.image?

    photo = Vips::Image.thumbnail_buffer(blob.download, LOGO, height: LOGO, crop: :centre)
    photo = photo.flatten(background: [ 255, 255, 255 ]) if photo.has_alpha?
    photo = photo.colourspace(:srgb)
    photo = photo.bandjoin([ photo, photo ]) if photo.bands == 1
    photo.cast(:uchar)
  rescue StandardError => e
    Rails.logger.warn("[PageOgCard] logo failed for page #{page.id}: #{e.class}: #{e.message}")
    nil
  end
end
