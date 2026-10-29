# frozen_string_literal: true

module Users
  # Password reset. Devise sends anyone who is already signed in away from the
  # reset form (straight to the feed), but the reset link often opens in the
  # app or a browser where the person is still signed in. A valid reset link
  # wins: sign them out and show the form.
  class PasswordsController < Devise::PasswordsController
    prepend_before_action :sign_out_for_reset_link, only: :edit

    private

    def sign_out_for_reset_link
      return unless user_signed_in? && params[:reset_password_token].present?

      sign_out(current_user)
    end
  end
end
