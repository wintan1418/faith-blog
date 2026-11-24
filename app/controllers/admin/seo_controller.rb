# frozen_string_literal: true

# Admin → Search & indexing: Google Search Console numbers (when connected),
# sitemap status, URL inspection, IndexNow submissions and their log.
class Admin::SeoController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  RECENT_WINDOW = 7.days
  LOG_SIZE = 30

  def show
    @google = SearchConsole.configured?
    @period = SearchConsole::PERIODS.key?(params[:period]) ? params[:period] : "28d"
    @indexnow_enabled = IndexNow.enabled?
    @indexnow_key = IndexNow.key
    @submissions = IndexingSubmission.recent.limit(LOG_SIZE)
    recent = IndexingSubmission.where(engine: "indexnow").since(RECENT_WINDOW.ago)
    @indexnow_week = { requests: recent.count, urls: recent.sum(:urls_count), failed: recent.where.not(status_code: [ 200, 202 ]).or(recent.where(status_code: nil)).count }
    @pending_count = IndexingPendingUrl.count
    return unless @google

    @reports = SearchConsoleReport.where(kind: report_kinds).index_by(&:kind)
    @inspected_url = params[:inspected].presence
    @inspection = SearchConsoleReport.for(inspection_kind(@inspected_url)) if @inspected_url
  end

  def refresh
    return redirect_to(admin_seo_path, alert: "Connect Google Search Console first.") unless SearchConsole.configured?

    SearchConsoleRefreshJob.perform_later
    redirect_to admin_seo_path, notice: "Refreshing from Google. Reload this page in a minute."
  end

  def sitemap
    return redirect_to(admin_seo_path, alert: "Connect Google Search Console first.") unless SearchConsole.configured?

    submission = SearchIndexingNightlyJob.submit_sitemap(trigger: "manual")
    if submission.success?
      SearchConsoleRefreshJob.perform_later
      redirect_to admin_seo_path(anchor: "sitemaps"), notice: "Sitemap submitted to Google."
    else
      redirect_to admin_seo_path(anchor: "sitemaps"), alert: "Google didn't take the sitemap: #{submission.response}"
    end
  end

  def inspect_url
    return redirect_to(admin_seo_path, alert: "Connect Google Search Console first.") unless SearchConsole.configured?

    url = params[:url].to_s.strip
    unless SearchIndexing.public_url?(url)
      return redirect_to admin_seo_path(anchor: "inspect"), alert: "Enter a public https://#{SearchIndexing::HOST} address."
    end

    begin
      SearchConsoleReport.store!(inspection_kind(url), data: SearchConsole.client.inspect_url(url).merge("url" => url))
    rescue SearchConsole::Error => e
      SearchConsoleReport.store!(inspection_kind(url), data: { "url" => url }, error: e.message)
    end
    redirect_to admin_seo_path(inspected: url, anchor: "inspect")
  end

  def index_now
    unless IndexNow.enabled?
      return redirect_to admin_seo_path(anchor: "indexnow"),
                         alert: "IndexNow only runs in production (set INDEXNOW_ENABLED=1 to allow it here)."
    end

    urls = if params[:scope] == "recent"
      SearchIndexing.recently_changed_urls(since: RECENT_WINDOW.ago)
    else
      url = params[:url].to_s.strip
      unless SearchIndexing.submittable_url?(url)
        return redirect_to admin_seo_path(anchor: "indexnow"),
                           alert: "That address isn't a public page search engines may index (private, anonymous, prayer and /join pages are never sent)."
      end
      [ url ]
    end
    return redirect_to(admin_seo_path(anchor: "indexnow"), notice: "No pages changed in the last 7 days.") if urls.empty?

    submissions = IndexNow.submit(urls, trigger: "manual")
    if submissions.all?(&:success?)
      redirect_to admin_seo_path(anchor: "log"), notice: "Sent #{helpers.pluralize(urls.size, 'page')} to IndexNow."
    else
      failed = submissions.reject(&:success?).first
      redirect_to admin_seo_path(anchor: "log"), alert: "IndexNow answered #{failed.status_code || 'nothing'}: #{failed.status_label}."
    end
  end

  private

  def report_kinds
    %w[status sitemaps pages_seen_3m] + SearchConsole::PERIODS.keys.flat_map { |p| %W[totals_#{p} queries_#{p} pages_#{p}] }
  end

  def inspection_kind(url)
    "inspection:#{Digest::SHA256.hexdigest(url.to_s)[0, 32]}"
  end
end
