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
      Post.find(reportable_id).tap { |post| raise ActiveRecord::RecordNotFound unless post.readable_by?(current_user) }
    when "Comment"
      Comment.find(reportable_id).tap { |comment| raise ActiveRecord::RecordNotFound unless comment.post.nil? || comment.post.readable_by?(current_user) }
    when "Resource"
      Resource.find(reportable_id)
    when "User"
      # A member (from Breathers around you); never yourself.
      User.active.where.not(id: current_user.id).find(reportable_id)
    when "Page"
      Page.find(reportable_id).tap { |page| raise ActiveRecord::RecordNotFound unless page.visible_to?(current_user) }
    when "Message"
      conversation = current_user.conversations.joins(:messages).where(messages: { id: reportable_id }).first!
      conversation.messages.find(reportable_id)
    else
      raise ActiveRecord::RecordNotFound
    end
  end
end
