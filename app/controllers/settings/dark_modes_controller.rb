module Settings
  class DarkModesController < ApplicationController
    before_action :authenticate_user!

    def update
      current_user.update(dark_mode: ActiveModel::Type::Boolean.new.cast(params[:dark])) if current_user.respond_to?(:dark_mode=)
      head :no_content
    end
  end
end
