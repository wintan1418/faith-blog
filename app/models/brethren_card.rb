class BrethrenCard < ApplicationRecord
  belongs_to :user

  # Who may see each contact detail (email, WhatsApp). Private by default:
  # a member's contact details are only shown to the people they choose.
  VISIBILITIES = { only_me: 0, chosen: 1, connections: 2, everyone: 3 }.freeze

  VISIBILITY_OPTIONS = {
    "only_me"     => { label: "Only me", hint: "Nobody else sees it." },
    "chosen"      => { label: "Connections I choose", hint: "Only the connections on your list. Add them in Settings → Privacy, or tap “Share my contact” on their profile or in a chat." },
    "connections" => { label: "All my connections", hint: "Everyone you're connected with." },
    "everyone"    => { label: "Everyone", hint: "Anyone who opens your card or your business card link, even people who aren't signed in." }
  }.freeze

  CONTACT_FIELDS = %i[email whatsapp].freeze

  enum :email_visibility, VISIBILITIES, prefix: true, validate: true
  enum :whatsapp_visibility, VISIBILITIES, prefix: true, validate: true

  validates :church_or_assembly, presence: true, on: :update
  validates :bio, presence: true, length: { maximum: 500 }, on: :update
  validates :occupation, presence: true, on: :update
  # Contact details are optional: nobody has to put an email or a number on
  # Brethreign to connect.
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true, if: :will_save_change_to_email?
  validates :whatsapp_number, format: { with: /\A\+?[\d\s\-().]{6,24}\z/, message: "should be a phone number, like +234 812 345 6789" },
                              allow_blank: true, if: :will_save_change_to_whatsapp_number?

  normalizes :email, with: ->(v) { v.to_s.strip.presence }
  normalizes :whatsapp_number, with: ->(v) { v.to_s.squish.presence }

  before_save :check_completeness
  after_commit -> { OnboardingChecklist.broadcast_refresh(user) }, if: -> { saved_change_to_is_complete? }

  # Save the two "who can see" settings from a form (unknown values are
  # ignored). Skips the card's other validations: a member with an unfinished
  # card can still make their contact details private.
  def self.apply_visibility(user, attrs)
    changes = attrs.to_h.slice("email_visibility", "whatsapp_visibility").select { |_, v| VISIBILITIES.key?(v.to_s.to_sym) }
    return if changes.empty?

    card = user.brethren_card || user.create_brethren_card
    card.update_columns(changes.transform_values(&:to_s).merge("updated_at" => Time.current))
    user.update_column(:contact_privacy_notice_pending, false) if user.contact_privacy_notice_pending?
  end

  def whatsapp_link
    return nil unless whatsapp_number.present?
    # Remove non-digits and create WhatsApp link
    clean_number = whatsapp_number.gsub(/\D/, "")
    "https://wa.me/#{clean_number}"
  end

  def gmail_link
    return nil unless email.present?
    "mailto:#{email}"
  end

  def complete?
    is_complete
  end

  def contact_value(field)
    field.to_sym == :email ? email : whatsapp_number
  end

  def visibility_for(field)
    public_send("#{field}_visibility")
  end

  def has_contact? = email.present? || whatsapp_number.present?

  # May `viewer` (a User, or nil when signed out) see this contact detail?
  # The owner and Brethreign admins always can. Nobody else sees a detail set
  # to "Only me", and a block hides everything. "Connections I choose" is the
  # owner's list (ContactShare) of people they're still connected with; "All
  # my connections" is every accepted connection; "Everyone" is public.
  #
  # `shared:` and `connected:` let lists pass what they already know, so a
  # page of 50 connections doesn't run 100 queries.
  def contact_visible_to?(field, viewer, shared: nil, connected: nil)
    return false if contact_value(field).blank?
    return true if viewer && (viewer.id == user_id || viewer.contact_privacy_exempt?)

    level = visibility_for(field)
    return false if level == "only_me"
    return false if viewer && blocked_with?(viewer)
    return true if level == "everyone"
    return false if viewer.nil?

    connected = connected_to?(viewer) if connected.nil?
    return false unless connected
    return true if level == "connections"

    shared.nil? ? shared_with?(viewer) : shared
  end

  # The contact details `viewer` may see: { email: "…", whatsapp: "…" }, only
  # the allowed keys.
  def visible_contact_for(viewer, **hints)
    CONTACT_FIELDS.each_with_object({}) do |field, out|
      out[field] = contact_value(field) if contact_visible_to?(field, viewer, **hints)
    end
  end

  def shared_with?(viewer)
    return false if viewer.nil?

    @shared_with ||= {}
    @shared_with.fetch(viewer.id) { @shared_with[viewer.id] = ContactShare.exists?(owner_id: user_id, viewer_id: viewer.id) }
  end

  # "Share my contact" means the person on the list can see it. A detail the
  # owner had at "Only me" opens to "Connections I choose" (only the list),
  # never wider.
  def open_to_chosen!
    changes = {}
    changes[:email_visibility] = :chosen if email.present? && email_visibility_only_me?
    changes[:whatsapp_visibility] = :chosen if whatsapp_number.present? && whatsapp_visibility_only_me?
    update_columns(changes.merge(updated_at: Time.current)) if changes.any?
    changes.keys
  end

  # Never put contact details into a JSON rendering by accident.
  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) | %w[email whatsapp_number]
    super(options)
  end

  private

  def connected_to?(viewer)
    @connected_to ||= {}
    @connected_to.fetch(viewer.id) { @connected_to[viewer.id] = user.connected_with?(viewer) }
  end

  def blocked_with?(viewer)
    @blocked_with ||= {}
    @blocked_with.fetch(viewer.id) { @blocked_with[viewer.id] = MessageBlock.between?(user_id, viewer.id) }
  end

  def check_completeness
    # Complete when the fellowship details are filled. Profile photo and
    # contact details are optional.
    self.is_complete = [
      church_or_assembly.present?,
      bio.present?,
      occupation.present?
    ].all?
  end
end
