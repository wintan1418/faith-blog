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

  private

  def invitation_params
    params.require(:invitation).permit(:email, :message)
  end
end
