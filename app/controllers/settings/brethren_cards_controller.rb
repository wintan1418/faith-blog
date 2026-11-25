module Settings
  class BrethrenCardsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_brethren_card

    def edit
      current_user.update_column(:contact_privacy_notice_pending, false) if current_user.contact_privacy_notice_pending?
    end

    def update
      if @brethren_card.update(brethren_card_params)
        # In the apps this closes the edit screen and goes back to where it was opened.
        recede_or_redirect_to user_path(current_user.username), notice: "Your Brethren Card has been updated!"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_brethren_card
      @brethren_card = current_user.brethren_card || current_user.build_brethren_card
    end

    def brethren_card_params
      params.expect(brethren_card: [ :church_or_assembly, :bio, :occupation, :whatsapp_number, :email,
                                           :email_visibility, :whatsapp_visibility ])
    end
  end
end
