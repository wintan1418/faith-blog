# frozen_string_literal: true

# /me — a stable link to the signed-in user's own profile.
# The mobile apps' Profile tab points here, since the app doesn't know the username.
class MeController < ApplicationController
  before_action :authenticate_user!

  def show
    redirect_to user_path(current_user.username)
  end
end
