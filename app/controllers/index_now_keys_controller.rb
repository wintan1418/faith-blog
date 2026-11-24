# frozen_string_literal: true

# /<key>.txt: IndexNow engines fetch this to confirm we own the key.
class IndexNowKeysController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    key = IndexNow.key
    if params[:indexnow_key] == "#{key}.txt"
      expires_in 1.day, public: true
      render plain: key, content_type: "text/plain"
    else
      head :not_found
    end
  end
end
