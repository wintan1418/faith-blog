# frozen_string_literal: true

# Sensitive actions (changing email or password, turning on two-step login,
# creating a Page) ask for a verified email first. Everything else works
# for unverified members.
module RequiresVerifiedEmail
  extend ActiveSupport::Concern

  VERIFY_FIRST = "Please verify your email first. It keeps your account safe, and takes a minute."

  private

  def require_verified_email!(return_to: request.get? ? request.fullpath : nil)
    return if current_user.nil? || current_user.email_verified?

    redirect_to email_verification_path(return_to: return_to), alert: VERIFY_FIRST
  end
end
