# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_report, only: [:show, :resolve, :dismiss]

  def index
    @reports = Report.includes(:reporter, :reportable).order(created_at: :desc).page(params[:page]).per(20)
    @pending_reports = @reports.pending
  end

  def show
  end

  def resolve
    @report.review!(current_user, :resolved, params[:notes])
    ModerationLog.log_action(moderator: current_user, action: "resolved_report", target: @report, notes: params[:notes])
    redirect_to admin_reports_path, notice: "Report resolved."
  end

  def dismiss
    @report.review!(current_user, :dismissed, params[:notes])
    ModerationLog.log_action(moderator: current_user, action: "dismissed_report", target: @report, notes: params[:notes])
    redirect_to admin_reports_path, notice: "Report dismissed."
  end

  private

  def set_report
    @report = Report.find(params[:id])
  end
end

