# frozen_string_literal: true

module Ai
  module Office
    # Picks the model for the Office. Precedence:
    #   1. OFFICE_STUB=1 or AI_MODERATION_STUB=1      -> Stub (no network)
    #   2. OFFICE_PROVIDER=<name> with its key set    -> that provider
    #   3. First key found                            -> anthropic > openai > gemini
    #   4. Nothing configured                         -> Stub
    # OFFICE_MODEL overrides the chosen provider's default model.
    class Client
      class Error < StandardError; end
      class ApiError < Error
        attr_reader :status

        def initialize(message = nil, status: nil)
          super(message)
          @status = status
        end
      end

      PROVIDERS = {
        "anthropic" => { klass: "Ai::Office::Providers::Anthropic", env_key: "ANTHROPIC_API_KEY" },
        "openai"    => { klass: "Ai::Office::Providers::Openai",    env_key: "OPENAI_API_KEY" },
        "gemini"    => { klass: "Ai::Office::Providers::Gemini",    env_key: "GEMINI_API_KEY" },
        "stub"      => { klass: "Ai::Office::Providers::Stub",      env_key: nil }
      }.freeze

      def self.provider_name
        return "stub" if ENV["OFFICE_STUB"] == "1" || ENV["AI_MODERATION_STUB"] == "1"

        explicit = ENV["OFFICE_PROVIDER"].to_s.downcase
        return explicit if PROVIDERS.key?(explicit) && key_present?(explicit)

        %w[anthropic openai gemini].find { |name| key_present?(name) } || "stub"
      end

      def self.key_present?(name)
        env_key = PROVIDERS.dig(name, :env_key)
        env_key.nil? || ENV[env_key].to_s.strip.present?
      end

      def self.build(provider: nil)
        name = provider || provider_name
        config = PROVIDERS.fetch(name)
        config[:klass].constantize.new(api_key: config[:env_key] && ENV[config[:env_key]], model: ENV["OFFICE_MODEL"].presence)
      end

      # "Claude (claude-opus-5-5)" for the Office header.
      def self.label
        provider = build
        "#{provider.display_name} · #{provider.model}"
      end
    end
  end
end
