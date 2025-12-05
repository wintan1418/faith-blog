module Settings
  class BrethrenCardsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_brethren_card

    def edit
    end

    def update
      if @brethren_card.update(brethren_card_params)
        redirect_to settings_brethren_card_path, notice: "Your Brethren Card has been updated!"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_brethren_card
      @brethren_card = current_user.brethren_card || current_user.build_brethren_card
    end

    def brethren_card_params
      params.require(:brethren_card).permit(
        :church_or_assembly,
        :bio,
        :occupation,
        :whatsapp_number,
        :email
      )
    end
  end
end

