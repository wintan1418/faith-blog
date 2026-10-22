# frozen_string_literal: true

# Whether we can send pushes to the iOS / Android apps. Each platform is
# off until its keys are in the environment (see config/push.yml).
module NativePushConfig
  module_function

  def apple?
    %w[APNS_KEY_ID APNS_KEY APNS_TEAM_ID].all? { |name| ENV[name].present? }
  end

  def google?
    %w[FCM_SERVICE_ACCOUNT_JSON FCM_PROJECT_ID].all? { |name| ENV[name].present? }
  end

  def configured_platforms
    [ ("apple" if apple?), ("google" if google?) ].compact
  end

  def configured?
    configured_platforms.any?
  end
end
