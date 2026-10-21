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

  # GET /settings/account/delete — explain what happens and ask for confirmation.
  def delete
  end

  # DELETE /settings/account — permanently delete the account and its content.
  # Confirmed by typing the username (works for Google sign-in users too,
  # who never set a password).
  def destroy
    unless params[:confirm_username].to_s.strip.casecmp?(current_user.username)
      flash.now[:alert] = "That doesn't match your username. Your account was not deleted."
      render :delete, status: :unprocessable_entity
      return
    end

    user = current_user
    user.destroy!
    sign_out(user)
    redirect_to root_path, status: :see_other,
      notice: "Your account and everything you shared have been deleted. Go in peace."
  end

  private

  def account_params
    params.require(:user).permit(:email, :username, :password, :password_confirmation)
  end
end
