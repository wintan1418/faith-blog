module Settings
  class DarkModesController < ApplicationController
    def update
      dark = ActiveModel::Type::Boolean.new.cast(params[:dark])
      current_user&.update(dark_mode: dark) if current_user&.respond_to?(:dark_mode=)

      head :no_content
    end
  end
end
