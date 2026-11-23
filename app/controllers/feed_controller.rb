# frozen_string_literal: true

class FeedController < ApplicationController
  before_action :authenticate_user!
  # Infinite scroll (?page=N) only appends cards; it never shows the sidebar or onboarding.
  before_action :load_sidebar_context, unless: :next_page?, except: :new_posts
  before_action :load_onboarding_progress, unless: :next_page?, except: :new_posts
  # The pill's background check isn't a page view.
  skip_after_action :track_page_view, only: :new_posts
  helper_method :feed_next_page_url, :feed_fresh?, :feed_as_of, :time_param_value

  # How many recent posts/reposts the feed looks at (ids and times only). Wide
  # enough that a burst from one author can be spread out among other members.
  POSTS_BUFFER    = 200
  RESHARES_BUFFER = 60
  PER_PAGE        = 20
  # Community-wide sidebar bits are the same for everyone: refresh every few minutes.
  SIDEBAR_TTL     = 5.minutes

  def index
    unless next_page?
      load_suggestions
      load_around_card
    end
    # Pinned breaths (admin-featured) lead the feed — a community noticeboard.
    @pinned_posts = feed_posts_scope.where(featured: true).recent.limit(2).to_a

    posts    = Post.published.where.not(id: @pinned_posts.map(&:id)).recent
    reshares = Reshare.order(created_at: :desc)
    # Posts newer than the last visit come first and get a small "New" dot.
    @feed_fresh_after = snapshot? ? param_time(:seen) : current_user.feed_seen_at
    @items = paged_feed(posts: posts, reshares: reshares, fresh_after: @feed_fresh_after)
    # They've now seen the top of the feed (written at most once a minute).
    current_user.mark_feed_seen!(feed_as_of) unless params[:page].to_i > 1
    respond_to_feed
  end

  # The "New posts" pill: how many feed posts arrived after `since` (the time
  # the page on screen was built) that this member hasn't seen, plus up to
  # three of their authors' faces. Same rules as the feed: published and
  # approved only, nobody blocked, and anonymous posts are counted but never
  # show their author. The page asks on load, when the app comes back to the
  # front, and when a live "post arrived" marker comes in.
  def new_posts
    since = [ param_time(:since), current_user.feed_seen_at ].compact.max
    if since
      scope = Post.published.where("posts.published_at > ?", since).where.not(user_id: current_user.id)
      blocked = current_user.blocked_user_ids
      scope = scope.where.not(user_id: blocked) if blocked.any?
      @new_posts_count = scope.count
      author_ids = scope.named.reorder(published_at: :desc).limit(30).pluck(:user_id).uniq.first(3)
      authors = User.includes(profile: { avatar_attachment: :blob }).where(id: author_ids).index_by(&:id)
      @new_posts_authors = author_ids.filter_map { |id| authors[id] }
    else
      @new_posts_count = 0
      @new_posts_authors = []
    end
    render partial: "feed/new_posts_pill", formats: [ :html ],
           locals: { count: @new_posts_count, authors: @new_posts_authors }
  end

  def threads
    @items = paged_feed(posts: Post.published.threads_or_active.recent)
    respond_to_feed
  end

  def trending
    posts = Post.published
                .where(published_at: 7.days.ago..)
                .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
    @items = paged_feed(posts: posts, keep_order: true)
    respond_to_feed
  end

  def following
    followed_user_ids = current_user.following.pluck(:id)

    # Anonymous breaths stay out of Following — showing one here would tell
    # you it came from someone you follow.
    posts    = Post.published.named.where(user_id: followed_user_ids).recent
    reshares = Reshare.where(user_id: followed_user_ids).order(created_at: :desc)
    @items = paged_feed(posts: posts, reshares: reshares)
    respond_to_feed
  end

  # The Updates tab: news, sports, jobs and free courses the bots brought in.
  # Kept apart from members' breaths; members choose which bots they see.
  def updates
    @updates_tab = true
    current_user.dismiss_card!("updates-intro") # they've found it; the banner can go
    @pinned_posts = []
    @bot_filter = Bots::Catalog.find(params[:bot])&.key
    @topic_filter = params[:topic] if @bot_filter == "news" && Bots::Catalog::NEWS_TOPICS.key?(params[:topic])

    scope = BotItem.live.includes(:bot_source).newest
    scope = @bot_filter ? scope.where(bot: @bot_filter) : scope.where.not(bot: current_user.hidden_bots)
    scope = scope.where(topic: @topic_filter) if @topic_filter
    @pagy, @bot_items = pagy(scope, items: PER_PAGE)
    @my_bot_reactions = current_user.likes.where(likeable_type: "BotItem", likeable_id: @bot_items.map(&:id))
                                    .index_by(&:likeable_id)

    respond_to do |format|
      format.html { render :index }
      format.turbo_stream do
        params[:page].present? ? render("bot_items/paginate") : render(:index, formats: [ :html ], content_type: "text/html")
      end
    end
  end

  private

  # The getting-started list (until it's finished or hidden) and the
  # first-visit tour (once per account). A few cheap EXISTS queries, and none
  # at all once the list is done.
  def load_onboarding_progress
    @show_tour = current_user.tour_completed_at.nil?
    @onboarding, @onboarding_celebrate = OnboardingChecklist.feed_state(current_user)
  end

  # Speed: work out the page from ids and times only (tiny queries), then load full
  # cards (author, photos, likes, tags…) for just that page's 20 items. Before, all
  # 60 posts + 60 reposts were loaded with everything attached on every request.
  #
  # Every page of one visit is cut from the same snapshot: only posts up to
  # `as_of` (the time page one was built), mixed with the same seed. So paging
  # never repeats or skips a card even while new posts arrive; those wait for
  # the New posts pill. FeedMix spreads out runs from one author.
  def paged_feed(posts:, reshares: nil, keep_order: false, fresh_after: nil)
    # Nothing from people you've blocked (or who blocked you), nor their reposts.
    if (blocked = current_user.blocked_user_ids).any?
      posts = posts.where.not(user_id: blocked)
      reshares = reshares.where.not(user_id: blocked).where.not(post_id: Post.where(user_id: blocked).select(:id)) if reshares
    end
    posts = posts.where(published_at: ..feed_as_of)
    entries = posts.limit(POSTS_BUFFER).pluck(:id, :published_at, :created_at, :user_id)
                   .map { |id, published_at, created_at, user_id| { kind: :post, id: id, at: published_at || created_at, author_id: user_id } }
    if reshares
      # A repost is grouped with the author of the post it shares: that's whose words fill the card.
      entries += reshares.where(created_at: ..feed_as_of).joins(:post).limit(RESHARES_BUFFER)
                         .pluck("reshares.id", "reshares.created_at", "posts.user_id")
                         .map { |id, at, user_id| { kind: :reshare, id: id, at: at, author_id: user_id } }
    end
    entries = FeedMix.call(entries, seed: "#{current_user.id}:#{feed_as_of.to_date}",
                                    fresh_after: fresh_after, keep_order: keep_order)

    @pagy, page = pagy_array(entries, items: PER_PAGE)

    post_ids    = page.filter_map { |e| e[:id] if e[:kind] == :post }
    reshare_ids = page.filter_map { |e| e[:id] if e[:kind] == :reshare }
    cards     = Post.includes(feed_post_includes).where(id: post_ids).index_by(&:id)
    reshared  = Reshare.includes(:user, post: feed_post_includes).where(id: reshare_ids).index_by(&:id)

    page.filter_map do |e|
      if e[:kind] == :post
        cards[e[:id]] && FeedItem.from_post(cards[e[:id]])
      else
        reshared[e[:id]]&.post&.readable_by?(current_user) && FeedItem.from_reshare(reshared[e[:id]])
      end
    end
  end

  # The moment this visit's feed was cut. Times travel in URLs as whole
  # microseconds (the database's precision), so page two cuts at exactly the
  # same instant as page one.
  def feed_as_of
    @feed_as_of ||= begin
      now = Time.zone.at(Rational(time_param_value(Time.current), 1_000_000))
      at = param_time(:as_of)
      at && at <= now ? at : now
    end
  end

  def time_param_value(time)
    (time.to_r * 1_000_000).to_i
  end

  # A later page of a visit that started earlier (infinite scroll carries the snapshot).
  def snapshot?
    params[:page].to_i > 1 && params[:as_of].present?
  end

  def param_time(key)
    value = params[key].to_i
    Time.zone.at(Rational(value, 1_000_000)) if value.positive?
  end

  # Posted since the member's last visit (not by them): gets a small "New" dot.
  def feed_fresh?(item)
    @feed_fresh_after.present? && item.timestamp > @feed_fresh_after && item.post.user_id != current_user.id
  end

  def feed_next_page_url
    url_for(page: @pagy.next, as_of: time_param_value(feed_as_of), seen: @feed_fresh_after && time_param_value(@feed_fresh_after))
  end

  def feed_posts_scope
    scope = Post.published.includes(feed_post_includes)
    blocked = current_user.blocked_user_ids
    blocked.any? ? scope.where.not(user_id: blocked) : scope
  end

  def feed_post_includes
    Post::CARD_INCLUDES
  end

  def respond_to_feed
    respond_to do |format|
      format.html { render :index }
      # Only infinite scroll (?page=N) wants the stream. A Turbo form that redirects
      # here (e.g. sign-in) also accepts streams but needs the full page.
      format.turbo_stream do
        if params[:page].present?
          render :paginate
        else
          render :index, formats: [ :html ], content_type: "text/html"
        end
      end
    end
  end

  # Only the infinite-scroll stream skips the sidebar. A full page at ?page=2 (reload,
  # Back, a shared link) still renders the sidebar, so it needs the data.
  # "Brethren you may know" row (first page only). Never let it break the feed.
  def load_suggestions
    @suggestions = BrethrenSuggestions.for(current_user, limit: 10)
    @suggestion_nudge = current_user.profile&.assembly.blank? && current_user.experiences.none?
  rescue StandardError => e
    Rails.logger.warn("[feed] suggestions failed: #{e.class}: #{e.message}")
    @suggestions = []
  end

  # "N breathers live in Akure" (or "Add your city"), until closed.
  def load_around_card
    profile = current_user.profile
    return if profile.nil? || profile.minor?

    if profile.city_id.blank?
      @around_card = { kind: :add_city, key: "around-add-city" }
    else
      preview = BreathersAround.new(current_user).city_preview
      if preview.count.positive?
        @around_card = { kind: :count, preview: preview, city: profile.city, key: "around-#{profile.city_id}-#{preview.count}" }
      end
    end
    @around_card = nil if @around_card && current_user.card_dismissed?(@around_card[:key])
  rescue StandardError => e
    Rails.logger.warn("[feed] around card failed: #{e.class}: #{e.message}")
    @around_card = nil
  end

  def next_page?
    params[:page].to_i > 1 && request.format.turbo_stream?
  end

  # Cached as ids (cheap to reload, safe across deploys) rather than whole records.
  # If the cache store is unavailable (e.g. its table is missing in production),
  # just compute the value: the feed must never fail because of caching.
  def cached_ids(key, &block)
    Rails.cache.fetch([ "feed-sidebar", key ], expires_in: SIDEBAR_TTL, &block)
  rescue StandardError => e
    Rails.logger.warn("[feed] cache unavailable (#{e.class}: #{e.message}); computing #{key} directly")
    block.call
  end

  def load_by_ids(scope, ids)
    records = scope.where(id: ids).index_by(&:id)
    ids.filter_map { |id| records[id] }
  end

  def load_sidebar_context
    @prayer_room = Room.where(id: cached_ids(:prayer_room) { Room.prayers.public_rooms.ordered.limit(1).pluck(:id) }).first
    prayer_room_ids = Room.prayers.select(:id)
    prayer_posts = Post.published.where(room_id: prayer_room_ids).recent

    @open_prayer_requests_count = cached_ids(:open_prayer_count) { prayer_posts.count }
    @open_prayer_requests = load_by_ids(Post.includes(:user, :room), cached_ids(:open_prayers) { prayer_posts.limit(3).pluck(:id) })

    @daily_verses  = load_by_ids(BibleVerse, cached_ids(:daily_verses) { BibleVerse.active.ordered.limit(20).pluck(:id) })
    @daily_breaths = load_by_ids(GoldenBreath, cached_ids(:daily_breaths) { GoldenBreath.active.ordered.limit(20).pluck(:id) })
    @birthdays_today = current_user.brethren_birthdays_today.to_a
    @user_reading_plan = current_user.user_reading_plans.where(completed: false).order(updated_at: :desc).first

    trending_ids = cached_ids(:trending) do
      Post.published.where(published_at: 7.days.ago..)
          .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
          .limit(4).pluck(:id)
    end
    @trending_breaths = load_by_ids(Post.includes(:user, :room), trending_ids)
    # The sidebar lists are shared by everyone (cached); drop blocked people per viewer.
    if (blocked = current_user.blocked_user_ids).any?
      @trending_breaths = @trending_breaths.reject { |post| blocked.include?(post.user_id) }
      @open_prayer_requests = @open_prayer_requests.reject { |post| blocked.include?(post.user_id) }
    end

    following_ids = current_user.following.pluck(:id) << current_user.id
    active_author_ids = Post.published
                            .where(published_at: 30.days.ago..)
                            .where.not(user_id: following_ids + current_user.blocked_user_ids)
                            .group(:user_id)
                            .order(Arel.sql("COUNT(*) DESC"))
                            .limit(3)
                            .pluck(:user_id)
    @who_to_brethren = User.where(id: active_author_ids).includes(:profile).to_a

    # Fallback: if no recent authors among non-followed, show 3 newest
    # active members so the widget never disappears.
    if @who_to_brethren.size < 3
      need = 3 - @who_to_brethren.size
      already_ids = following_ids + @who_to_brethren.map(&:id)
      fillers = User.respond_to?(:active) ? User.active : User.all
      fillers = fillers.where.not(id: already_ids).order(created_at: :desc).limit(need).includes(:profile)
      @who_to_brethren += fillers.to_a
    end

    @release_announcement = Announcement.where(id: cached_ids(:release) { Announcement.latest_release&.id }).first
    @new_member_announcements = load_by_ids(Announcement.includes(:user),
                                            cached_ids(:new_members) { Announcement.recent_new_members(limit: 4).pluck(:id) })
  end
end
