# frozen_string_literal: true

module Ai
  module Office
    # The functions the Office assistant may call. Read-only tools just answer;
    # tools that make things return a card so the founder stays in charge
    # (the only exception is draft_breath with publish: true, which the
    # prompt reserves for an explicit "post it without asking").
    module Tools
      # Who's asking and where the result will land.
      Context = Data.define(:user, :conversation)

      # result:     what the model is told. card: what the founder sees (nil for none).
      # blob:       an Active Storage blob to show on the card (flyers).
      # after_save: called with the saved tool message once it has an id (the
      #             card's id the model uses later); returns more for result.
      Outcome = Data.define(:result, :card, :blob, :after_save) do
        def initialize(result:, card: nil, blob: nil, after_save: nil)
          super
        end

        def self.error(message) = new(result: { "error" => message })
      end

      def self.registry
        {
          "draft_breath" => DraftBreath,
          "update_breath" => UpdateBreath,
          "generate_flyer" => GenerateFlyer,
          "draft_email" => DraftEmail,
          "draft_announcement" => DraftAnnouncement,
          "site_stats" => SiteStats,
          "recent_activity" => RecentActivity
        }
      end

      def self.definitions = registry.values.map(&:definition)

      def self.dispatch(name, input, context)
        klass = registry[name.to_s]
        return Outcome.error("Unknown tool #{name}") unless klass

        klass.new(input.is_a?(Hash) ? input.stringify_keys : {}, context).call
      rescue StandardError => e
        Rails.logger.error("[Office] tool #{name} failed: #{e.class}: #{e.message}")
        Outcome.error("#{name} failed: #{e.message.truncate(300)}")
      end

      # Shared plumbing for the tool classes.
      class Base
        def initialize(input, context)
          @input = input
          @context = context
        end

        private

        attr_reader :input, :context

        def user = context.user
        def conversation = context.conversation

        # A breath card in this conversation, by the id the model was given.
        def find_breath(id)
          message = conversation.messages.find_by(id: id.to_i) if id.present?
          message if BreathCard.breath?(message)
        end

        # A public room by (roughly) its name.
        def find_room(name)
          return nil if name.blank?

          rooms = Room.public_rooms
          rooms.find_by("LOWER(name) = ?", name.to_s.downcase.strip) ||
            rooms.find_by(slug: name.to_s.parameterize) ||
            rooms.where("name ILIKE ?", "%#{Room.sanitize_sql_like(name.to_s.strip)}%").first
        end

        # A flyer (or any message with an image) in this conversation.
        def find_image(id) = BreathCard.image_source(conversation, id)
        def routes = Rails.application.routes.url_helpers
      end
    end
  end
end
