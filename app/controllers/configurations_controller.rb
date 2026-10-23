# frozen_string_literal: true

# Hotwire Native path configuration, fetched by the iOS and Android apps on launch.
# Changing the rules here changes app behaviour without an App Store release.
class ConfigurationsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  MODAL_PATTERNS = [ "/new$", "/edit$" ].freeze
  # Inside a chat, pulling down scrolls back through older messages; it must not reload the page.
  CHAT_PATTERNS = [ "/inbox/\\d+$" ].freeze

  def ios_v1
    render json: {
      settings: {},
      rules: [
        { patterns: [ ".*" ], properties: { context: "default", pull_to_refresh_enabled: true } },
        { patterns: MODAL_PATTERNS, properties: { context: "modal", pull_to_refresh_enabled: false } },
        { patterns: CHAT_PATTERNS, properties: { pull_to_refresh_enabled: false } }
      ]
    }
  end

  def android_v1
    render json: {
      settings: {},
      rules: [
        { patterns: [ ".*" ], properties: { context: "default", uri: "hotwire://fragment/web", pull_to_refresh_enabled: true } },
        { patterns: MODAL_PATTERNS, properties: { context: "modal", uri: "hotwire://fragment/web/modal/sheet", pull_to_refresh_enabled: false } },
        { patterns: CHAT_PATTERNS, properties: { pull_to_refresh_enabled: false } }
      ]
    }
  end
end
