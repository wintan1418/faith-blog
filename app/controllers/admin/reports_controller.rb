# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_report, only: [ :show, :resolve, :dismiss, :retire_question ]

  # Report types with their own filter tab ("Quiz questions" shows players'
  # reports of faulty Bible Quiz questions).
  TYPE_FILTERS = { "BibleQuizQuestion" => "Quiz questions" }.freeze

  def index
    @type = params[:type].presence_in(TYPE_FILTERS.keys)
    reports = Report.includes(:reporter, :reportable).order(created_at: :desc)
    reports = reports.where(reportable_type: @type) if @type
    @pagy, @reports = pagy(reports, items: 20)
    @pending_reports = (@type ? Report.where(reportable_type: @type) : Report).pending.count
  end

  def show
  end

  def resolve
    @report.review!(current_user, :resolved, params[:notes])
    ModerationLog.log_action(moderator: current_user, action: "resolved_report", target: @report, notes: params[:notes])
    redirect_to admin_reports_path, notice: "Report resolved."
  end

  # Quiz question reports: the question really is faulty, so keep it out of
  # the quiz for good (it stays in the database for the record).
  def retire_question
    question = @report.reportable
    return redirect_to(admin_report_path(@report), alert: "Not a quiz question.") unless question.is_a?(BibleQuizQuestion)

    question.retire!
    question.reports.pending.find_each { |r| r.review!(current_user, :resolved, params[:notes].presence || "Question retired.") }
    ModerationLog.log_action(moderator: current_user, action: "resolved_report", target: @report, notes: "Retired quiz question ##{question.id}")
    redirect_to admin_reports_path(type: "BibleQuizQuestion"), notice: "Question retired from the quiz."
  end

  def dismiss
    @report.review!(current_user, :dismissed, params[:notes])
    # A quiz question that was fine goes back into the quiz once nobody else's report is waiting.
    question = @report.reportable
    question.restore! if question.is_a?(BibleQuizQuestion) && question.reports.pending.none?
    ModerationLog.log_action(moderator: current_user, action: "dismissed_report", target: @report, notes: params[:notes])
    redirect_to admin_reports_path, notice: "Report dismissed."
  end

  private

  def set_report
    @report = Report.find(params[:id])
  end
end
