# frozen_string_literal: true

# The getting-started list on the feed. Each step ticks itself from what the
# member has really done, so there is nothing to tick by hand. Once every step
# is done the list says so once and never comes back (users.onboarding_completed_at);
# "Hide for now" puts it away (users.onboarding_dismissed_at) and Settings can
# bring it back.
#
# The same steps drive the Onboarding panel on the admin dashboard.
class OnboardingChecklist
  Step = Struct.new(:key, :title, :hint, :done, keyword_init: true) do
    alias_method :done?, :done
  end

  # key => [title, hint]. Order is the order members see.
  STEPS = {
    photo: [ "Add a profile photo", "A face helps the brethren know who they're talking to." ],
    breath: [ "Take your first breath", "A verse, a prayer, or simply what's on your heart." ],
    prayed: [ "Pray for someone", "Tap Praying on a request so they know they're not alone." ],
    room: [ "Join a room", "Smaller spaces for prayer, Bible study and more." ],
    card: [ "Complete your Brethren Card", "Your private card for the brethren you connect with." ],
    connected: [ "Follow or connect with someone", "Their breaths will start to fill your feed." ],
    professional: [ "Set up your professional profile", "Your work, skills and church service, so faith and work meet." ]
  }.freeze

  # The blog guide that explains each step in more detail.
  GUIDES = {
    photo: "getting-started-on-brethreign",
    breath: "take-your-first-breath",
    prayed: "praying-together-on-brethreign",
    room: "getting-started-on-brethreign",
    card: "your-brethren-card-and-connecting",
    connected: "brethren-you-may-know",
    professional: "set-up-your-professional-profile"
  }.freeze

  def self.guide_slug(key)
    slug = GUIDES[key]
    slug if slug && BlogArticle.all.any? { |a| a.slug == slug }
  end

  # Which members have done each step, as a narrowing of a User relation.
  # Used for one member (the feed) and for everyone (the admin dashboard).
  SCOPES = {
    photo: ->(rel) {
      rel.where(id: Profile.joins(:avatar_attachment).select(:user_id))
    },
    breath: ->(rel) { rel.where(id: Post.published.select(:user_id)) },
    prayed: ->(rel) {
      rel.where(id: PrayerIntercession.select(:user_id)).or(rel.where(id: Like.praying.select(:user_id)))
    },
    room: ->(rel) { rel.where(id: RoomMembership.select(:user_id)) },
    card: ->(rel) { rel.where(id: BrethrenCard.where(is_complete: true).select(:user_id)) },
    connected: ->(rel) {
      rel.where(id: Follow.select(:follower_id))
         .or(rel.where(id: ConnectionRequest.select(:sender_id)))
         .or(rel.where(id: ConnectionRequest.accepted.select(:receiver_id)))
    },
    professional: ->(rel) {
      rel.where(id: Profile.where.not(headline: [ nil, "" ]).select(:user_id)).or(rel.where(id: Experience.select(:user_id)))
    }
  }.freeze

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def steps
    @steps ||= begin
      done = done_keys
      STEPS.map { |key, (title, hint)| Step.new(key: key, title: title, hint: hint, done: done.include?(key)) }
    end
  end

  def done_count = steps.count(&:done?)
  def total = steps.size
  def complete? = done_count == total
  def next_step = steps.find { |s| !s.done? }

  # Should the feed show the list at all? Never after it was finished (even
  # if a step is later undone), and not while hidden.
  def visible?
    user.onboarding_completed_at.nil? && user.onboarding_dismissed_at.nil?
  end

  # Called on the feed: the first time everything is done, remember it and
  # show the celebration line once. Returns true only on that visit.
  def record_completion!
    return false unless user.onboarding_completed_at.nil? && complete?

    user.update_column(:onboarding_completed_at, Time.current)
    true
  end

  # ── Admin: how many members have done each step ─────────────────────

  # rows: [[title, count]] for members in `members` (a User relation).
  def self.step_counts(members = User.all)
    STEPS.map { |key, (title, _)| [ title, SCOPES.fetch(key).call(members).count ] }
  end

  def self.all_steps_count(members = User.all)
    SCOPES.values.reduce(members) { |rel, scope| scope.call(rel) }.count
  end

  private

  # One small query per step for this member (the feed shows the list only
  # until it is finished or hidden).
  def done_keys
    me = User.where(id: user.id)
    SCOPES.filter_map { |key, scope| key if scope.call(me).exists? }
  end
end
