# frozen_string_literal: true

# Which bots show in a member's Updates tab (all of them unless switched off).
class Settings::UpdatesController < ApplicationController
  before_action :authenticate_user!

  def update
    shown = Array(params[:bots]) & Bots::Catalog.keys
    current_user.update!(hidden_bots: Bots::Catalog.keys - shown)
    redirect_to feed_updates_path, notice: "Updates saved."
  end
end
