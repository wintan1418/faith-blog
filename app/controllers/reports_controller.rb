# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :authenticate_user!

  def create
    reportable = find_reportable
    report = current_user.reports.build(
      reportable: reportable,
      reason: params[:reason].presence || "Submitted for moderator review."
    )

    if report.save
      redirect_back fallback_location: root_path, notice: "Thanks. A moderator will review it."
    else
      redirect_back fallback_location: root_path, alert: report.errors.full_messages.to_sentence
    end
  end

  private

  def find_reportable
    reportable_type = params[:reportable_type].to_s
    reportable_id = params[:reportable_id]

    case reportable_type
    when "Post"
      Post.find(reportable_id)
    when "Comment"
      Comment.find(reportable_id)
    when "Resource"
      Resource.find(reportable_id)
    when "Message"
      conversation = current_user.conversations.joins(:messages).where(messages: { id: reportable_id }).first!
      conversation.messages.find(reportable_id)
    else
      raise ActiveRecord::RecordNotFound
    end
  end
end
