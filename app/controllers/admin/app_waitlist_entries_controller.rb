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
