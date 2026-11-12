# frozen_string_literal: true

module Ai
  module Office
    module Tools
      class DraftBreath < Base
        def self.definition
          rooms = Room.public_rooms.ordered.pluck(:name)
          {
            name: "draft_breath",
            description: "Prepare a breath (a short Brethreign post) as a card the founder can post now, schedule or edit. " \
                         "Set publish to true ONLY when the founder has explicitly said in this conversation to post it without checking with them. " \
                         "Pass flyer_id (from generate_flyer) to show that image with the breath. Returns breath_id; use update_breath with it to change this breath later. " \
                         "Rooms: #{rooms.any? ? rooms.join(', ') : 'none'} (or leave room empty for the main feed).",
            parameters: {
              type: "object",
              properties: {
                body: { type: "string", description: "The breath text. Plain text; blank lines between paragraphs. Usually under 280 words." },
                title: { type: "string", description: "Optional short title. Most breaths have none." },
                room: { type: "string", description: "Optional room name from the list." },
                prayer_request: { type: "boolean", description: "True if this is a prayer request." },
                flyer_id: { type: "integer", description: "Optional flyer_id of an image made in this conversation, to attach to the breath." },
                schedule_at: { type: "string", description: "Optional time to post, ISO 8601 in Lagos time, e.g. 2026-11-12T08:00." },
                publish: { type: "boolean", description: "Post (or schedule) immediately without a confirmation card. Only on explicit instruction." }
              },
              required: [ "body" ]
            }
          }
        end

        def call
          body = input["body"].to_s.strip
          return Outcome.error("The breath needs some text.") if body.blank?

          room = find_room(input["room"])
          image = find_image(input["flyer_id"])
          return Outcome.error("flyer_id #{input['flyer_id']} isn't an image in this conversation.") if input["flyer_id"].present? && !image

          schedule_at = BreathPublisher.parse_time(input["schedule_at"])
          card = {
            "kind" => "breath", "status" => "draft",
            "title" => input["title"].to_s.strip.truncate(200),
            "body" => body,
            "room_id" => room&.id, "room_name" => room&.name,
            "prayer" => input["prayer_request"] == true,
            "schedule_at" => schedule_at&.iso8601,
            "image_message_id" => image&.id,
            "author" => BreathPublisher.author_for(user).username
          }

          return publish(card, schedule_at) if input["publish"] == true

          Outcome.new(
            result: { "status" => "card_shown", "note" => "The founder sees the breath with Post now, Schedule and Edit buttons. Nothing is posted yet.",
                      "room" => room&.name, "schedule_at" => card["schedule_at"], "flyer_id" => image&.id }.compact,
            card: card.compact, after_save: ->(message) { { "breath_id" => message.id } }
          )
        end

        private

        def publish(card, schedule_at)
          outcome = BreathPublisher.new(card: card, admin: user, schedule_at: schedule_at).call
          unless outcome.ok?
            return Outcome.new(result: { "error" => "Couldn't post: #{outcome.errors.to_sentence}. Shown as a card instead." },
                               card: card.merge("error" => outcome.errors.to_sentence),
                               after_save: ->(message) { { "breath_id" => message.id } })
          end

          post = outcome.post
          card = card.merge(BreathPublisher.card_attrs_for(post)).compact
          Outcome.new(result: { "status" => card["status"], "post_url" => routes.post_path(post), "scheduled_for" => post.scheduled_for&.iso8601 },
                      card: card, after_save: ->(message) { { "breath_id" => message.id } })
        end
      end
    end
  end
end
