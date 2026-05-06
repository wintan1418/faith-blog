# frozen_string_literal: true

class InvitationMailer < ApplicationMailer
  def invite
    @invitation = params.fetch(:invitation)
    @inviter = @invitation.inviter
    @join_url = new_user_registration_url(invite: @invitation.token)

    mail(
      to: @invitation.email,
      subject: "Hey — #{@inviter.display_name} invited you to come and breathe."
    )
  end
end
