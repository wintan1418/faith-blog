# frozen_string_literal: true

class Admin::ReportsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_report, only: [ :show, :resolve, :dismiss, :retire_question, :edit_question, :update_question ]

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

  # A quiz question report is only "resolved" once the question is fixed
  # (edited since the report) or out of the quiz — two reports were once
  # resolved while their questions stayed live and unchanged.
  def resolve
    question = @report.reportable
    if question.is_a?(BibleQuizQuestion) && !question_dealt_with?(question)
      return redirect_to(admin_report_path(@report),
                         alert: "This question is still in the quiz unchanged. Edit it or retire it to resolve the report.")
    end

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

  def edit_question
    @question = @report.reportable
    redirect_to(admin_report_path(@report), alert: "Not a quiz question.") unless @question.is_a?(BibleQuizQuestion)
  end

  # Fix the reported question: it goes back into the quiz (flags cleared)
  # and every pending report of it is resolved.
  def update_question
    @question = @report.reportable
    return redirect_to(admin_report_path(@report), alert: "Not a quiz question.") unless @question.is_a?(BibleQuizQuestion)

    attrs = params.require(:bible_quiz_question).permit(:prompt, :correct_index, :reference, :explanation, choices: [])
    attrs[:choices] = Array(attrs[:choices]).map { |c| c.to_s.strip }
    attrs[:correct_index] = attrs[:correct_index].to_i
    @question.assign_attributes(attrs.merge(flags_count: 0))
    unless @question.save
      return render :edit_question, status: :unprocessable_entity
    end

    note = params[:notes].presence || "Question edited."
    @question.reports.pending.find_each { |r| r.review!(current_user, :resolved, note) }
    ModerationLog.log_action(moderator: current_user, action: "resolved_report", target: @report, notes: "Edited quiz question ##{@question.id}")
    redirect_to admin_reports_path(type: "BibleQuizQuestion"), notice: "Question updated and back in the quiz."
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

  def question_dealt_with?(question)
    question.retired? || question.updated_at > @report.created_at
  end
  helper_method :question_dealt_with?
end
