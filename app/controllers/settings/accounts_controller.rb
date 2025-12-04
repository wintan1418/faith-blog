# frozen_string_literal: true

class Settings::AccountsController < ApplicationController
  before_action :authenticate_user!

  def edit
  end

  def update
    if current_user.update(account_params)
      bypass_sign_in(current_user)
      redirect_to settings_account_path, notice: "Account updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:user).permit(:email, :username, :password, :password_confirmation)
  end
end

