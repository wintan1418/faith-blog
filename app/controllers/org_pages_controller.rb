# frozen_string_literal: true

# Pages for churches, ministries, fellowships, businesses, schools, NGOs and
# communities: the /pages directory, making one (/pages/new, a few short
# steps), the page itself (/p/<handle>: Posts, About, People) and managing it
# (details, pictures, team, verification).
#
# (Named OrgPages because PagesController serves the About / Terms pages.)
class OrgPagesController < ApplicationController
  PAGE_FIELDS = %i[name handle category tagline about website email phone city_id location founded_year size_range
                   tradition service_times logo cover remove_logo remove_cover].freeze

  before_action :authenticate_user!, except: %i[index show]
  before_action :set_page, only: %i[show manage update request_verification]
  before_action :require_manager!, only: %i[manage update request_verification]
  member_rate_limit to: 5, within: 1.hour, only: :create, name: "page-create"
  member_rate_limit to: 120, within: 10.minutes, only: :handle_check, name: "page-handle", json: true

  def index
    directory = PageDirectory.new(current_user)
    @query = params[:q].to_s.squish.first(100)
    @category = params[:category].presence_in(Page.categories.keys)
    @pagy, @pages = pagy(directory.search(@query, category: @category), items: 24)
    @browsing = @query.blank? && @category.nil?
    if @browsing && params[:page].to_i <= 1
      @near = directory.near.to_a
      @suggested = directory.suggested.to_a
      @my_pages = user_signed_in? ? current_user.postable_pages : []
      @city = directory.city
    end
    @followed_ids = user_signed_in? ? current_user.page_follows.where(page_id: (@pages.to_a + @near.to_a + @suggested.to_a).map(&:id)).pluck(:page_id) : []
  end

  def new
    @block_reason = Page.creation_block_reason(current_user)
    @page = Page.new(category: params[:category].presence_in(Page.categories.keys) || "church")
  end

  def create
    @block_reason = Page.creation_block_reason(current_user)
    return redirect_to(new_org_page_path, alert: @block_reason) if @block_reason

    @page = Page.new(page_params.except(:remove_logo, :remove_cover).merge(created_by: current_user))
    saved = Page.transaction do
      @page.save && @page.memberships.create!(user: current_user, role: :owner, status: :active, accepted_at: Time.current)
    end
    if saved
      redirect_to org_page_path(@page), notice: "#{@page.name} is live. Invite your team and write your first post."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @page.errors.add(:handle, "has just been taken")
    render :new, status: :unprocessable_entity
  end

  # Is this handle free? (The create form checks as you type.)
  def handle_check
    handle = params[:handle].to_s.strip.delete_prefix("@")
    problem = if handle.length < 3 then "needs at least 3 letters"
    elsif handle.length > 30 then "is too long (30 at most)"
    elsif !handle.match?(/\A[a-zA-Z0-9_]+\z/) then "may only use letters, numbers and underscores"
    else PageHandle.problem_with(handle) || ("is taken" if Page.by_handle(handle).where.not(id: params[:page_id]).exists?)
    end
    render json: { handle: handle, available: problem.nil?, message: problem && "@#{handle} #{problem}",
                   suggestion: (PageHandle.suggest(params[:name]) if params[:name].present?) }
  end

  def show
    @tab = params[:tab].presence_in(%w[about people]) || "posts"
    @role = @page.role_for(current_user)
    @following = @page.followed_by?(current_user)
    @invite = current_user && @page.memberships.pending.find_by(user_id: current_user.id)
    case @tab
    when "posts"
      scope = @page.public_posts.for_cards.recent
      blocked = current_user&.blocked_user_ids.to_a
      scope = scope.where.not(user_id: blocked) if blocked.any?
      @pagy, @posts = pagy(scope, items: 15)
    when "people"
      @people = people_on_page
    end
    respond_to do |format|
      format.html
      format.turbo_stream if params[:page].present? && @tab == "posts"
    end
  end

  def manage
    @tab = params[:tab].presence_in(%w[details team verification]) || "details"
    @team = @page.memberships.includes(user: { profile: { avatar_attachment: :blob } }).order(:role, :created_at).to_a
  end

  def update
    attrs = page_params
    attrs = attrs.except(:handle) unless @page.owner?(current_user) || current_user.admin_or_moderator?
    @page.logo.purge_later if attrs.delete(:remove_logo) == "1" && @page.logo.attached? && attrs[:logo].blank?
    @page.cover.purge_later if attrs.delete(:remove_cover) == "1" && @page.cover.attached? && attrs[:cover].blank?
    if @page.update(attrs)
      redirect_to manage_org_page_path(@page), notice: "Page saved."
    else
      @tab = "details"
      @team = @page.memberships.includes(:user).order(:role, :created_at).to_a
      render :manage, status: :unprocessable_entity
    end
  end

  def request_verification
    note = params[:note].to_s.strip
    if @page.verified?
      redirect_to manage_org_page_path(@page, tab: "verification"), notice: "This page is already verified."
    elsif note.length < 10
      redirect_to manage_org_page_path(@page, tab: "verification"), alert: "Tell us a little about how we can confirm the page is yours (a link helps)."
    else
      @page.request_verification!(note)
      redirect_to manage_org_page_path(@page, tab: "verification"), notice: "Thanks. Our team will look at your request."
    end
  end

  private

  def set_page
    @page = Page.includes(:city, logo_attachment: :blob, cover_attachment: :blob).find_by_handle!(params[:handle])
    raise ActiveRecord::RecordNotFound unless @page.visible_to?(current_user)
  end

  def require_manager!
    return if @page.manager?(current_user) || current_user.admin? || current_user.super_admin?

    redirect_to org_page_path(@page), alert: "Only the page's owner and admins can manage it."
  end

  def page_params
    attrs = params.expect(page: [ *PAGE_FIELDS, { socials: Page::SOCIAL_NETWORKS.keys } ])
    attrs[:city_id] = nil if attrs.key?(:city_id) && attrs[:city_id].blank?
    attrs
  end

  # Members who list the page on their profile (and said to show them here).
  def people_on_page
    blocked = current_user&.blocked_user_ids.to_a
    rows = Experience.listed_for_page(@page).includes(user: { profile: { avatar_attachment: :blob } })
                     .order(current: :desc, start_on: :desc).limit(200).to_a
    rows.reject { |e| blocked.include?(e.user_id) }.uniq(&:user_id).first(60)
  end
end
