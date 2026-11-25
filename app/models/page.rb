# frozen_string_literal: true

# A Page: a church, ministry, fellowship, business, school, NGO, community or
# media outlet on Brethreign (like a LinkedIn Company Page). Pages are run by
# members (PageMembership: owner, admins, editors), followed by members
# (PageFollow), and post as themselves: a page post keeps its writer in
# posts.user_id for moderation and audit, but is shown as the page.
#
# Public at /p/<handle>. Verified (the badge) is set by Brethreign admins only,
# after a page asks. `plan` is the tier: everything is free for now; "Pro
# pages" will build on it.
class Page < ApplicationRecord
  include AttachmentValidatable

  CATEGORIES = {
    "church"     => { label: "Church",              icon: "church" },
    "ministry"   => { label: "Ministry",            icon: "handheart" },
    "fellowship" => { label: "Fellowship / campus", icon: "users" },
    "business"   => { label: "Business",            icon: "briefcase" },
    "school"     => { label: "School",              icon: "graduationcap" },
    "nonprofit"  => { label: "Non-profit / NGO",    icon: "globe" },
    "community"  => { label: "Community",           icon: "sprout" },
    "media"      => { label: "Media",               icon: "megaphone" }
  }.freeze
  SIZE_RANGES = [ "1-10", "11-50", "51-200", "201-500", "501-1,000", "1,000-5,000", "5,000+" ].freeze
  # Pages a member may own (staff aren't limited).
  MAX_OWNED = 3
  # New accounts wait this long before making a page, unless their email is
  # proven (signed up with Google / Apple).
  MIN_ACCOUNT_AGE = 7.days
  LOGO_MAX_BYTES = 8.megabytes
  COVER_MAX_BYTES = 10.megabytes

  enum :category, CATEGORIES.keys.each_with_index.to_h, validate: true
  enum :status, { active: 0, suspended: 1 }, validate: true
  enum :verification_status, { unrequested: 0, requested: 1, approved: 2, declined: 3 }, prefix: :verification
  enum :plan, { free: 0, pro: 1 }, prefix: :plan

  belongs_to :city, optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :memberships, class_name: "PageMembership", dependent: :delete_all
  has_many :active_memberships, -> { where(status: :active) }, class_name: "PageMembership", inverse_of: :page
  has_many :members, through: :active_memberships, source: :user
  has_many :follows, class_name: "PageFollow", dependent: :delete_all
  has_many :followers, through: :follows, source: :user
  has_many :posts, dependent: :nullify
  has_many :experiences, dependent: :nullify
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many :ai_moderation_reviews, as: :reviewable, dependent: :destroy

  has_one_attached :logo
  has_one_attached :cover
  # The generated link-preview image (PageOgCard).
  has_one_attached :og_card

  # Search vectors are written by a database trigger (SiteSearch::PageSchema).
  self.ignored_columns += %w[searchable]

  # Set by admins and the official-page task: skips the reserved-handle and
  # impersonation checks (never from a member's form).
  attr_accessor :staff_override
  # Form ticks on the manage page ("Remove the logo").
  attr_accessor :remove_logo, :remove_cover

  normalizes :handle, with: ->(h) { h.to_s.strip.delete_prefix("@") }
  normalizes :name, :tagline, :tradition, :location, with: ->(v) { v.to_s.squish.presence }
  normalizes :website, with: ->(v) { PageHandle.normalize_url(v) }
  # The page's own social accounts: { "instagram" => "https://instagram.com/…" }.
  SOCIAL_NETWORKS = { "x" => "X", "instagram" => "Instagram", "facebook" => "Facebook", "youtube" => "YouTube",
                      "linkedin" => "LinkedIn", "substack" => "Substack" }.freeze
  normalizes :socials, with: ->(v) {
    (v.respond_to?(:to_h) ? v.to_h : {}).to_h { |k, url| [ k.to_s, PageHandle.normalize_url(url.to_s.strip.first(255)) ] }
      .select { |k, url| SOCIAL_NETWORKS.key?(k) && url.present? }
  }
  normalizes :email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.to_s.squish.presence }

  validates :name, presence: true, length: { minimum: 2, maximum: 80 }
  validates :handle, presence: true, length: { minimum: 3, maximum: 30 },
                     format: { with: /\A[a-zA-Z0-9_]+\z/, message: "may only use letters, numbers and underscores" }
  validates :handle, uniqueness: { case_sensitive: false }
  validates :tagline, length: { maximum: 160 }
  validates :about, length: { maximum: 5_000 }
  validates :website, length: { maximum: 255 }
  validate :socials_are_links
  validates :website, format: { with: %r{\Ahttps?://[^\s/$.?#][^\s]*\z}i, message: "should be a web address" }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, length: { maximum: 40 }, format: { with: /\A[+\d\s().\-]*\z/, message: "may only use digits, spaces and + ( ) -" }
  validates :location, length: { maximum: 100 }
  validates :tradition, length: { maximum: 120 }
  validates :service_times, length: { maximum: 600 }
  validates :size_range, inclusion: { in: SIZE_RANGES }, allow_blank: true
  validates :founded_year, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: ->(_) { Date.current.year } },
                           allow_nil: true
  validate :handle_is_allowed, if: -> { will_save_change_to_handle? && !staff_override }
  validate :name_is_allowed, if: -> { will_save_change_to_name? && !staff_override }
  validate :logo_ok
  validate :cover_ok
  validate :language_is_clean

  scope :listed, -> { where(status: :active) }
  scope :verified, -> { where.not(verified_at: nil) }
  scope :by_handle, ->(handle) { where("lower(pages.handle) = ?", handle.to_s.delete_prefix("@").downcase) }

  # New logos and covers get the same AI look as profile photos.
  before_save { @images_changed = attachment_changes.keys & %w[logo cover] }
  after_commit :moderate_images, if: -> { @images_changed.present? }

  def self.find_by_handle!(handle) = by_handle(handle).first!

  def to_param = handle

  def category_label = CATEGORIES.dig(category, :label) || category.to_s.humanize
  def category_icon = CATEGORIES.dig(category, :icon) || "building"
  def verified? = verified_at.present?
  def initial = name.to_s.strip.first.to_s.upcase.presence || "P"
  def place = city&.label.presence || location

  # Short place for cards: "Akure, Nigeria".
  def short_place
    return location if city.nil?

    [ city.name, city.country_name ].compact_blank.join(", ")
  end

  def service_times_lines = service_times.to_s.lines.map(&:strip).compact_blank.first(12)

  # ── Who runs it ─────────────────────────────────────────────────────

  def membership_for(user)
    return unless user

    @membership_for ||= {}
    @membership_for.fetch(user.id) { @membership_for[user.id] = active_memberships.find_by(user_id: user.id) }
  end

  def role_for(user) = membership_for(user)&.role
  def owner?(user) = role_for(user) == "owner"
  # Owner or admin: edit the page, manage people, ask for verification.
  def manager?(user) = %w[owner admin].include?(role_for(user))
  # Anyone who may post as the page.
  def editor?(user) = role_for(user).present?

  def owners = members.merge(PageMembership.where(role: :owner))
  def managers = members.merge(PageMembership.where(role: %i[owner admin]))
  def owner = owners.first

  def staff?(user) = user.respond_to?(:admin_or_moderator?) && user.admin_or_moderator?

  # A suspended page is gone for everyone but its own people and staff.
  def visible_to?(viewer)
    active? || editor?(viewer) || staff?(viewer)
  end

  def followed_by?(user) = user.present? && follows.exists?(user_id: user.id)

  # Posts the public may see on the page.
  def public_posts = Post.published.where(page_id: id)

  # ── Creating one ────────────────────────────────────────────────────

  VERIFY_EMAIL_REASON = "Please verify your email address first. It keeps your page and your account safe."

  # Why this member can't make a page right now, or nil when they can.
  def self.creation_block_reason(user)
    return "Sign in to make a page." unless user
    return nil if user.admin_or_moderator?
    return VERIFY_EMAIL_REASON unless user.email_verified?
    return "Pages can be made by members aged 18 and over." if user.profile&.minor?
    return "Your account can't make pages right now." if user.risk_profile&.at_least?(:restricted)
    unless user.provider.present? || (user.created_at && user.created_at <= MIN_ACCOUNT_AGE.ago)
      return "New accounts can make a page after #{MIN_ACCOUNT_AGE.in_days.to_i} days " \
             "(or straight away if you signed up with Google or Apple)."
    end
    if PageMembership.where(user: user, role: :owner, status: :active).count >= MAX_OWNED
      return "You already own #{MAX_OWNED} pages, the most one member can have."
    end

    nil
  end

  def self.creatable_by?(user) = creation_block_reason(user).nil?

  # ── Verification ────────────────────────────────────────────────────

  def request_verification!(note)
    update!(verification_status: :requested, verification_note: note.to_s.strip.first(1_000), verification_requested_at: Time.current)
  end

  def verify!(admin)
    update!(verified_at: Time.current, verified_by: admin, verification_status: :approved)
    managers.each { |user| Notification.create(user: user, actor: admin, notifiable: self, notification_type: :page_verified) }
  end

  def unverify!
    update!(verified_at: nil, verified_by: nil, verification_status: :unrequested)
  end

  def decline_verification!
    update!(verification_status: :declined)
  end

  def suspend! = update!(status: :suspended, suspended_at: Time.current)
  def reinstate! = update!(status: :active, suspended_at: nil)

  # True when the name looks like a famous church, denomination or body
  # (admins check these before verifying).
  def protected_name? = PageHandle.protected_name?(name) || PageHandle.protected_handle?(handle)

  private

  def handle_is_allowed
    reason = PageHandle.problem_with(handle)
    errors.add(:handle, reason) if reason
  end

  def name_is_allowed
    errors.add(:name, "can't claim to be official or verified") if name.to_s.match?(/\b(official|verified)\b/i)
    errors.add(:name, "can't use the Brethreign name") if name.to_s.match?(/brethreign/i)
  end

  def logo_ok = validate_image_attachment(:logo, max_bytes: LOGO_MAX_BYTES)
  def cover_ok = validate_image_attachment(:cover, max_bytes: COVER_MAX_BYTES)

  def language_is_clean
    text = [ name, handle, tagline, about ].compact.join(" ")
    errors.add(:base, CleanLanguage::MESSAGE) if CleanLanguage.offensive?(text)
  end

  def moderate_images
    names = @images_changed
    @images_changed = nil
    names.each do |name|
      next unless public_send(name).attached?

      Ai::Moderation::Client.stub? ? PageImageModerationJob.perform_now(self, name) : PageImageModerationJob.perform_later(self, name)
    end
  end

  def socials_are_links
    bad = socials.to_h.reject { |_k, url| url.to_s.match?(%r{\Ahttps?://[^\s/$.?#][^\s]*\z}i) }
    bad.each_key { |k| errors.add(:socials, "#{SOCIAL_NETWORKS[k] || k} should be a web address") }
  end
end
