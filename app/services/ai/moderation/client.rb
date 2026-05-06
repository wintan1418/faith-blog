# frozen_string_literal: true

module Ai
  module Moderation
    # Dispatches the moderation call to whichever provider is configured.
    # Provider precedence:
    #   1. AI_MODERATION_STUB=1            -> Stub (no network)
    #   2. AI_MODERATION_PROVIDER=<name>   -> explicit choice (gemini/openai/anthropic/stub)
    #   3. First env key found             -> gemini > openai > anthropic
    #   4. Fallback                        -> Stub
    class Client
      class Error      < StandardError; end
      class ConfigError < Error; end
      class ApiError    < Error; end

      PROVIDERS = {
        "gemini"    => { klass: Providers::Gemini,    env_key: "GEMINI_API_KEY" },
        "openai"    => { klass: Providers::Openai,    env_key: "OPENAI_API_KEY" },
        "anthropic" => { klass: Providers::Anthropic, env_key: "ANTHROPIC_API_KEY" },
        "stub"      => { klass: Providers::Stub,      env_key: nil }
      }.freeze

      def self.call(system:, user:)
        new.call(system: system, user: user)
      end

      def self.stub?
        resolve_provider_name == "stub"
      end

      def self.provider_name
        resolve_provider_name
      end

      def self.resolve_provider_name
        return "stub" if ENV["AI_MODERATION_STUB"] == "1"

        explicit = ENV["AI_MODERATION_PROVIDER"].to_s.downcase
        return explicit if PROVIDERS.key?(explicit) && key_present_for?(explicit)

        %w[gemini openai anthropic].each do |name|
          return name if key_present_for?(name)
        end

        "stub"
      end

      def self.key_present_for?(name)
        env_key = PROVIDERS.dig(name, :env_key)
        return true if env_key.nil? # stub has no key

        ENV[env_key].to_s.strip.length.positive?
      end

      def initialize(provider: nil)
        name = provider || self.class.resolve_provider_name
        config = PROVIDERS.fetch(name) { raise ConfigError, "unknown provider: #{name}" }
        api_key = config[:env_key] ? ENV[config[:env_key]] : nil

        @provider_name = name
        @impl = config[:klass].new(api_key: api_key)
      end

      def call(system:, user:)
        @impl.call(system: system, user: user)
      end

      attr_reader :provider_name
    end
  end
end
