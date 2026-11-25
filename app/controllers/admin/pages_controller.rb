# frozen_string_literal: true

# Admin → Pages: every page, verification requests first; verify / unverify,
# decline a request, suspend / reinstate. Reports about pages come through
# Admin → Reports like everything else.
class Admin::PagesController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_page, except: :index

  FILTERS = %w[requests verified suspended protected].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS)
    scope = Page.includes(:city, logo_attachment: :blob).order(created_at: :desc)
    scope = case @filter
    when "requests" then scope.verification_requested.reorder(:verification_requested_at)
    when "verified" then scope.verified
    when "suspended" then scope.suspended
    else scope
    end
    @query = params[:q].to_s.squish.first(80)
    scope = scope.where("pages.name ILIKE :q OR pages.handle ILIKE :q", q: "%#{Page.sanitize_sql_like(@query)}%") if @query.present?
    scope = scope.select(&:protected_name?) if @filter == "protected"
    @pagy, @pages = scope.is_a?(Array) ? pagy_array(scope, items: 30) : pagy(scope, items: 30)
    @counts = { requests: Page.verification_requested.count, verified: Page.verified.count,
                suspended: Page.suspended.count, all: Page.count }
  end

  def show
    @team = @page.memberships.includes(:user).order(:role)
    @reports = @page.reports.includes(:reporter).order(created_at: :desc).limit(20)
  end

  def verify
    @page.verify!(current_user)
    log("verified_page")
    redirect_to admin_page_path(@page), notice: "#{@page.name} is verified."
  end

  def unverify
    @page.unverify!
    log("unverified_page")
    redirect_to admin_page_path(@page), notice: "Verification removed."
  end

  def decline
    @page.decline_verification!
    log("declined_page_verification")
    redirect_to admin_pages_path(filter: "requests"), notice: "Request declined."
  end

  def suspend
    @page.suspend!
    log("suspended_page")
    redirect_to admin_page_path(@page), notice: "#{@page.name} is suspended: hidden with its posts."
  end

  def reinstate
    @page.reinstate!
    log("reinstated_page")
    redirect_to admin_page_path(@page), notice: "#{@page.name} is back."
  end

  private

  def set_page
    @page = Page.find_by_handle!(params[:handle])
  end

  def log(action)
    ModerationLog.log_action(moderator: current_user, action: action, target: @page, notes: params[:notes])
  rescue StandardError => e
    Rails.logger.warn("[admin-pages] log failed: #{e.message}")
  end
end
