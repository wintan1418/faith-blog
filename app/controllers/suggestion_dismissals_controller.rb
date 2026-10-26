# frozen_string_literal: true

# "×" on a Brethren-you-may-know card: don't suggest this person again.
class SuggestionDismissalsController < ApplicationController
  before_action :authenticate_user!

  def create
    @dismissed = User.find(params[:user_id])
    current_user.suggestion_dismissals.find_or_create_by!(dismissed_user: @dismissed)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(helpers.dom_id(@dismissed, :suggestion)) }
      format.html { redirect_back fallback_location: people_path }
    end
  end
end
