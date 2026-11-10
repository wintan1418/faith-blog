# frozen_string_literal: true

class Admin::DashboardController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  def index
    @stats = AdminDashboardStats.new(params[:days])
  end
end
