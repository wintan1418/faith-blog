# frozen_string_literal: true

require "csv"

# Admin → App waitlist: who asked to hear when the iPhone / Android app is out.
# The emails are personal data, so this is admins only, like the member list.
class Admin::AppWaitlistEntriesController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  def index
    respond_to do |format|
      format.html do
        @counts = AppWaitlistEntry.platform_counts
        @total = @counts.values.sum
        @pagy, @entries = pagy(AppWaitlistEntry.newest_first, items: 100)
      end
      format.csv do
        send_data csv_for(AppWaitlistEntry.newest_first),
                  filename: "brethreign-app-waitlist-#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
  end

  # POST /admin/app-waitlist/notify/:platform — "the app is out" email to everyone
  # waiting for that platform who hasn't had it yet.
  def notify
    platform = params[:platform]
    unless WaitlistMailer.live?(platform)
      return redirect_to admin_app_waitlist_entries_path, alert: "Set #{WaitlistMailer::STORES.dig(platform, :env)} on the server first, so the email has a store link."
    end

    waiting = AppWaitlistEntry.waiting_for(platform).count
    WaitlistLaunchJob.perform_later(platform)
    redirect_to admin_app_waitlist_entries_path,
                notice: "Sending the #{WaitlistMailer::STORES.dig(platform, :name)} launch email to #{waiting} #{'person'.pluralize(waiting)}."
  end

  private

  def csv_for(entries)
    CSV.generate do |csv|
      csv << %w[email platform source signed_up_at updated_at]
      entries.find_each(order: :desc) do |e|
        csv << [ e.email, e.platform, e.source, e.created_at.utc.iso8601, e.updated_at.utc.iso8601 ]
      end
    end
  end
end
