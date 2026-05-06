# frozen_string_literal: true

class InvitationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @invitation = current_user.sent_invitations.build
    @invitations = current_user.sent_invitations.includes(:invited_user).recent
  end

  def create
    @invitation = current_user.sent_invitations.find_or_initialize_by(email: invitation_params[:email].to_s.strip.downcase)
    @invitation.assign_attributes(invitation_params)

    if @invitation.accepted?
      @invitations = current_user.sent_invitations.includes(:invited_user).recent
      @invitation.errors.add(:email, "has already accepted your invitation")
      render :index, status: :unprocessable_entity
    elsif @invitation.save
      @invitation.deliver!
      redirect_to invitations_path, notice: "Invitation sent to #{@invitation.email}."
    else
      @invitations = current_user.sent_invitations.includes(:invited_user).recent
      render :index, status: :unprocessable_entity
    end
  end

  def resend
    invitation = current_user.sent_invitations.find(params[:id])
    if invitation.accepted?
      redirect_to invitations_path, alert: "That invitation has already been accepted."
      return
    end

    invitation.deliver!
    redirect_to invitations_path, notice: "Invitation resent to #{invitation.email}."
  end

  BULK_LIMIT_PER_REQUEST = 100
  BULK_LIMIT_PER_DAY     = 300

  def bulk
    raw  = params[:bulk_emails].to_s
    note = params[:bulk_message].to_s

    emails = raw.split(/[\s,;]+/).map { |e| e.to_s.strip.downcase }.reject(&:empty?).uniq

    if emails.empty?
      redirect_to invitations_path, alert: "Add at least one email address to send invites."
      return
    end

    if emails.size > BULK_LIMIT_PER_REQUEST
      redirect_to invitations_path, alert: "Too many addresses at once. Send up to #{BULK_LIMIT_PER_REQUEST} per batch."
      return
    end

    sent_today = current_user.sent_invitations.where("created_at > ?", 24.hours.ago).count
    if sent_today + emails.size > BULK_LIMIT_PER_DAY
      remaining = [ BULK_LIMIT_PER_DAY - sent_today, 0 ].max
      redirect_to invitations_path, alert: "Daily invite cap reached. You can send #{remaining} more in the next 24 hours."
      return
    end

    valid_format    = emails.select { |e| URI::MailTo::EMAIL_REGEXP.match?(e) }
    invalid_emails  = emails - valid_format
    already_users   = User.where(email: valid_format).pluck(:email)
    already_invited = current_user.sent_invitations.where(email: valid_format).pluck(:email)
    to_send         = valid_format - already_users - already_invited

    sent_count = 0
    to_send.each do |email|
      invitation = current_user.sent_invitations.build(email: email, message: note.presence)
      if invitation.save
        invitation.deliver!
        sent_count += 1
      end
    end

    parts = []
    parts << "Sent #{view_context.pluralize(sent_count, "invitation")}." if sent_count.positive?
    parts << "Skipped #{already_users.size} already on the platform." if already_users.any?
    parts << "Skipped #{already_invited.size} already invited by you." if already_invited.any?
    parts << "Skipped #{invalid_emails.size} invalid (#{invalid_emails.first(3).join(", ")}#{"…" if invalid_emails.size > 3})." if invalid_emails.any?

    flash[parts.empty? ? :alert : :notice] = parts.join(" ").presence || "No invites went out."
    redirect_to invitations_path
  end

  private

  def invitation_params
    params.require(:invitation).permit(:email, :message)
  end
end
