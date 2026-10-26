# frozen_string_literal: true

class FeedController < ApplicationController
  before_action :authenticate_user!
  # Infinite scroll (?page=N) only appends cards; it never shows the sidebar or onboarding.
  before_action :load_sidebar_context, unless: :next_page?
  before_action :load_onboarding_progress, unless: :next_page?

  POSTS_BUFFER    = 60
  RESHARES_BUFFER = 60
  PER_PAGE        = 20
  # Community-wide sidebar bits are the same for everyone: refresh every few minutes.
  SIDEBAR_TTL     = 5.minutes

  def index
    load_suggestions unless next_page?
    # Pinned breaths (admin-featured) lead the feed — a community noticeboard.
    @pinned_posts = feed_posts_scope.where(featured: true).recent.limit(2).to_a

    posts    = Post.published.where.not(id: @pinned_posts.map(&:id)).recent
    reshares = Reshare.order(created_at: :desc)
    @items = paged_feed(posts: posts, reshares: reshares)
    respond_to_feed
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

    posts    = Post.published.where(user_id: followed_user_ids).recent
    reshares = Reshare.where(user_id: followed_user_ids).order(created_at: :desc)
    @items = paged_feed(posts: posts, reshares: reshares)
    respond_to_feed
  end

  private

  # The three activation steps behind the progress ring. Cheap EXISTS
  # queries; the ring renders only while something is still missing.
  def load_onboarding_progress
    @onboard = {
      followed: current_user.following.exists?,
      roomed:   current_user.room_memberships.exists?,
      breathed: current_user.posts.published.exists?
    }
    @onboard_done = @onboard.values.count(true)
  end

  # Speed: work out the page from ids and times only (tiny queries), then load full
  # cards (author, photos, likes, tags…) for just that page's 20 items. Before, all
  # 60 posts + 60 reposts were loaded with everything attached on every request.
  def paged_feed(posts:, reshares: nil, keep_order: false)
    entries = posts.limit(POSTS_BUFFER).pluck(:id, :published_at, :created_at)
                   .map { |id, published_at, created_at| [ :post, id, published_at || created_at ] }
    if reshares
      entries += reshares.limit(RESHARES_BUFFER).pluck(:id, :created_at).map { |id, at| [ :reshare, id, at ] }
    end
    entries = entries.sort_by { |_kind, _id, at| -at.to_i } unless keep_order

    @pagy, page = pagy_array(entries, items: PER_PAGE)

    post_ids    = page.filter_map { |kind, id, _| id if kind == :post }
    reshare_ids = page.filter_map { |kind, id, _| id if kind == :reshare }
    cards     = Post.includes(feed_post_includes).where(id: post_ids).index_by(&:id)
    reshared  = Reshare.includes(:user, post: feed_post_includes).where(id: reshare_ids).index_by(&:id)

    page.filter_map do |kind, id, _|
      if kind == :post
        cards[id] && FeedItem.from_post(cards[id])
      else
        reshared[id]&.post && FeedItem.from_reshare(reshared[id])
      end
    end
  end

  def feed_posts_scope
    Post.published.includes(feed_post_includes)
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

    following_ids = current_user.following.pluck(:id) << current_user.id
    active_author_ids = Post.published
                            .where(published_at: 30.days.ago..)
                            .where.not(user_id: following_ids)
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

    # Brand-new users see an onboarding card: no posts, no follows. Once they
    # take their first action the condition flips and the card stops rendering.
    @show_onboarding = current_user.posts.none? && current_user.following.empty?
    @onboarding_rooms = Room.public_rooms.ordered.limit(3) if @show_onboarding

    @release_announcement = Announcement.where(id: cached_ids(:release) { Announcement.latest_release&.id }).first
    @new_member_announcements = load_by_ids(Announcement.includes(:user),
                                            cached_ids(:new_members) { Announcement.recent_new_members(limit: 4).pluck(:id) })
  end
end
