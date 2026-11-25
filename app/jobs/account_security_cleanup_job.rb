# frozen_string_literal: true

# Forgets spent sign-in / verification codes (kept a day for rate limits),
# security events after 13 months, and devices signed out for over 90 days.
class AccountSecurityCleanupJob < ApplicationJob
  queue_as :bulk

  def perform
    SecurityCode.prune!
    SecurityEvent.prune!
    UserDevice.where(signed_out_at: ...90.days.ago).in_batches(of: 1_000).delete_all
  end
end
