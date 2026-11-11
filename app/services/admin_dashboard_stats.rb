# frozen_string_literal: true

# Numbers for Admin → Dashboard over a chosen period (7, 30 or 90 days, Lagos time),
# each compared with the period before it.
class AdminDashboardStats
  TZ = "Africa/Lagos"
  RANGES = [ 7, 30, 90 ].freeze
  OWN_DOMAINS = %w[brethreign.com www.brethreign.com].freeze

  # Referrers that are the same place under different hostnames.
  SOURCE_ALIASES = {
    /(^|\.)facebook\.com$|^fb\.me$/ => "Facebook",
    /(^|\.)instagram\.com$/ => "Instagram",
    /(^|\.)whatsapp\.(com|net)$|^wa\.me$/ => "WhatsApp",
    /(^|\.)google\.[a-z.]+$|^com\.google\./ => "Google",
    /(^|\.)bing\.com$/ => "Bing",
    /(^|\.)linkedin\.com$|^lnkd\.in$/ => "LinkedIn",
    /(^|\.)(x|twitter)\.com$|^t\.co$/ => "X",
    /(^|\.)youtube\.com$|^youtu\.be$/ => "YouTube",
    /(^|\.)tiktok\.com$/ => "TikTok"
  }.freeze

  Kpi = Struct.new(:label, :value, :previous, :note, keyword_init: true) do
    def change
      return nil if previous.nil? || previous.zero?

      ((value - previous) * 100.0 / previous).round
    end
  end

  attr_reader :days, :from, :to, :prev_from

  def initialize(days)
    @days = RANGES.include?(days.to_i) ? days.to_i : 30
    @to = Time.current
    @from = @to.in_time_zone(TZ).beginning_of_day - (@days - 1).days
    @prev_from = @from - @days.days
  end

  def period = from..to
  def previous_period = prev_from...from
  def dates = (0...days).map { |i| (from + i.days).to_date }

  # ── Headline numbers ──────────────────────────────────────────────

  def kpis
    [
      Kpi.new(label: "Visitors", value: visitors(period), previous: visitors(previous_period), note: "unique people on the site or app"),
      Kpi.new(label: "New members", value: User.where(created_at: period).count, previous: User.where(created_at: previous_period).count, note: "#{User.count} members in total"),
      Kpi.new(label: "Active members", value: User.where(last_seen_at: 7.days.ago..).count, previous: nil, note: "seen in the last 7 days · #{User.where(last_seen_at: Time.current.beginning_of_day..).count} today"),
      Kpi.new(label: "Breaths", value: Post.where(created_at: period).count, previous: Post.where(created_at: previous_period).count, note: "posts and threads"),
      Kpi.new(label: "Prayers", value: prayers(period), previous: prayers(previous_period), note: "#{PrayerIntercession.where(created_at: period).count} times someone prayed along"),
      Kpi.new(label: "Conversations", value: talk(period), previous: talk(previous_period), note: "comments and chat messages")
    ]
  end

  # ── Daily series ──────────────────────────────────────────────────

  def visitors_by_day = fill(Ahoy::Visit.where(started_at: period).group(day_sql("ahoy_visits", "started_at")).distinct.count(:visitor_token))
  def page_views_by_day = daily(Ahoy::Event.where(name: "$view"), :time)
  def signups_by_day = daily(User.all)

  def activity_series
    [
      [ "Breaths", daily(Post.all) ],
      [ "Comments", daily(Comment.all) ],
      [ "Chat messages", daily(Message.all) ],
      [ "Prayed along", daily(PrayerIntercession.all) ]
    ]
  end

  # ── Traffic ───────────────────────────────────────────────────────

  def page_views = Ahoy::Event.where(name: "$view", time: period).count

  def sources
    rows = Ahoy::Visit.where(started_at: period).group(:utm_source, :referring_domain).count
    tally = Hash.new(0)
    rows.each { |(utm, domain), n| tally[source_name(utm, domain)] += n }
    top(tally)
  end

  def landing_pages
    rows = Ahoy::Visit.where(started_at: period).where.not(landing_page: nil).group(:landing_page).order(count_all: :desc).limit(300).count
    tally = Hash.new(0)
    rows.each { |url, n| tally[url_path(url)] += n }
    top(tally)
  end

  def top_pages
    top(Ahoy::Event.where(name: "$view", time: period).group(Arel.sql("properties->>'path'")).order(count_all: :desc).limit(8).count)
  end

  def countries
    top(Ahoy::Visit.where(started_at: period).group(Arel.sql("COALESCE(country, '??')")).count)
  end

  def devices
    rows = Ahoy::Visit.where(started_at: period).group(:platform, :device_type).count
    tally = Hash.new(0)
    rows.each do |(platform, device), n|
      label = case platform
      when "android_app" then "Android app"
      when "ios_app" then "iPhone app"
      else device == "Desktop" ? "Web on a computer" : "Web on a phone or tablet"
      end
      tally[label] += n
    end
    top(tally)
  end

  # ── Members ───────────────────────────────────────────────────────

  # Of the people who joined in this period, how many took each next step.
  def funnel
    joined = User.where(created_at: period)
    ids = joined.ids
    return [] if ids.empty?

    with_photo = ActiveStorage::Attachment.where(record_type: "Profile", name: "avatar")
                                          .where(record_id: Profile.where(user_id: ids).select(:id)).distinct.count(:record_id)
    posted = Post.where(user_id: ids).distinct.count(:user_id)
    connected = ConnectionRequest.accepted.where(sender_id: ids).pluck(:sender_id)
                                 .concat(ConnectionRequest.accepted.where(receiver_id: ids).pluck(:receiver_id)).uniq.size
    [ [ "Joined", ids.size ], [ "Added a photo", with_photo ], [ "Shared a breath", posted ], [ "Made a connection", connected ] ]
  end

  def app_users = User.where.not(android_app_version: nil).count
  def professional_profiles = Profile.where.not(headline: [ nil, "" ]).count

  def top_rooms
    counts = Post.where(created_at: period).where.not(room_id: nil).group(:room_id).order(count_all: :desc).limit(5).count
    rooms = Room.where(id: counts.keys).index_by(&:id)
    counts.filter_map { |id, n| [ rooms[id], n ] if rooms[id] }
  end

  def top_members
    counts = Post.where(created_at: period).group(:user_id).order(count_all: :desc).limit(5).count
    users = User.includes(profile: { avatar_attachment: :blob }).where(id: counts.keys).index_by(&:id)
    counts.filter_map { |id, n| [ users[id], n ] if users[id] }
  end

  def recent_members = User.includes(profile: { avatar_attachment: :blob }).order(created_at: :desc).limit(6)

  # ── Online now (live; ignores the chosen period) ──────────────────
  # Admin counts and lists everyone, including members who hide their online
  # status from other members (Settings → Privacy).

  ONLINE_LIST_LIMIT = 60

  def online_now = User.active.online.count
  def active_last_15_minutes = User.active.where(last_seen_at: 15.minutes.ago..).count
  def active_today = User.active.where(last_seen_at: Time.current.in_time_zone(TZ).beginning_of_day..).count

  def online_members
    User.active.online.includes(profile: { avatar_attachment: :blob })
        .order(last_seen_at: :desc).limit(ONLINE_LIST_LIMIT)
  end

  # ── Safety ────────────────────────────────────────────────────────

  def safety
    [
      [ "Reports to review", Report.pending.count, Rails.application.routes.url_helpers.admin_reports_path ],
      [ "AI moderation queue", AiModerationReview.where(status: %i[pending flagged]).count, Rails.application.routes.url_helpers.admin_moderation_reviews_path ],
      [ "Breaths held for review", Post.moderation_pending_review.count, Rails.application.routes.url_helpers.admin_posts_path ],
      [ "Resources to approve", Resource.pending.count, Rails.application.routes.url_helpers.admin_resources_path ],
      [ "Chat messages removed", Message.where(removed_at: period).count, nil ]
    ]
  end

  # "NG" → "🇳🇬 Nigeria"
  def self.country_label(code)
    return "Unknown" if code.blank? || code == "??"

    flag = code.upcase.chars.map { |c| (c.ord + 127_397).chr(Encoding::UTF_8) }.join
    "#{flag} #{COUNTRY_NAMES.fetch(code.upcase, code.upcase)}"
  end

  COUNTRY_NAMES = {
    "NG" => "Nigeria", "GH" => "Ghana", "KE" => "Kenya", "ZA" => "South Africa", "US" => "United States",
    "GB" => "United Kingdom", "CA" => "Canada", "IE" => "Ireland", "DE" => "Germany", "FR" => "France",
    "NL" => "Netherlands", "IN" => "India", "AE" => "UAE", "AU" => "Australia", "BR" => "Brazil",
    "PH" => "Philippines", "KR" => "South Korea", "CN" => "China", "UG" => "Uganda", "RW" => "Rwanda",
    "CM" => "Cameroon", "TZ" => "Tanzania", "ZM" => "Zambia", "ZW" => "Zimbabwe", "SG" => "Singapore"
  }.freeze

  private

  def visitors(range) = Ahoy::Visit.where(started_at: range).distinct.count(:visitor_token)
  def prayers(range) = Post.where(created_at: range).where.not(prayer_status: :not_a_prayer).count
  def talk(range) = Comment.where(created_at: range).count + Message.where(created_at: range).count

  # Day (Lagos time) of a timestamp, for the columns the charts use. Fixed SQL, no outside input.
  DAY_SQL = %w[ahoy_visits.started_at ahoy_events.time users.created_at posts.created_at comments.created_at
               messages.created_at prayer_intercessions.created_at].to_h do |col|
    [ col, Arel.sql("DATE(#{col} AT TIME ZONE 'UTC' AT TIME ZONE 'Africa/Lagos')") ]
  end.freeze

  def day_sql(table, column) = DAY_SQL.fetch("#{table}.#{column}")

  def daily(scope, column = :created_at)
    fill(scope.where(column => period).group(day_sql(scope.table_name, column)).count)
  end

  def fill(counts) = dates.map { |d| [ d, counts[d] || 0 ] }

  def top(tally, limit = 8) = tally.sort_by { |_, n| -n }.first(limit)

  def source_name(utm, domain)
    if utm.present?
      key = utm.to_s.strip.downcase
      return SOURCE_ALIASES.values.find { |name| name.downcase == key } || key.capitalize
    end

    host = domain.to_s.downcase.delete_prefix("www.").delete_prefix("m.").delete_prefix("l.").delete_prefix("lm.")
    return "Direct or app" if host.blank? || OWN_DOMAINS.include?(host) || OWN_DOMAINS.include?("www.#{host}")

    SOURCE_ALIASES.each { |pattern, name| return name if host.match?(pattern) }
    host
  end

  def url_path(url)
    URI.parse(url.to_s).path.presence || "/"
  rescue URI::InvalidURIError
    url.to_s.split("?").first
  end
end
