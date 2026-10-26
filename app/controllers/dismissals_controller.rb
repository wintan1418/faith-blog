# frozen_string_literal: true

# Remembers a closed card on the account (see User#dismiss_card!).
class DismissalsController < ApplicationController
  before_action :authenticate_user!

  def create
    current_user.dismiss_card!(params[:key]) ? head(:no_content) : head(:unprocessable_entity)
  end
end
