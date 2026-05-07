# frozen_string_literal: true

class ScriptureController < ApplicationController
  before_action :authenticate_user!

  def show
    reference = params[:reference].to_s.strip
    head :bad_request and return if reference.empty? || reference.length > 80

    payload = ScriptureLookup.lookup(reference)
    if payload
      render json: payload
    else
      render json: { error: "not found" }, status: :not_found
    end
  end
end
