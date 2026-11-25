# frozen_string_literal: true

module Users
  # "Resend unlock instructions" — rate limited like password reset.
  class UnlocksController < Devise::UnlocksController
    include AuthRateLimiting

    throttle_auth only: :create, per_ip: 5, per_email: 3, within: 15.minutes

    # The unlock link came by email, so the address is verified too.
    def show
      super do |resource|
        EmailVerification.verified!(resource, request: request) if resource.persisted? && resource.errors.empty?
      end
    end
  end
end
