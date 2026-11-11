# frozen_string_literal: true

# Admin → Dashboard's live "Online now" card, reloaded every ~15s as a Turbo Frame.
class Admin::OnlineController < ApplicationController
  before_action :authenticate_admin!
  skip_after_action :track_page_view

  def index
    render partial: "admin/dashboard/online", locals: { stats: AdminDashboardStats.new(nil) }
  end
end
