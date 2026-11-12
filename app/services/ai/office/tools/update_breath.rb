# frozen_string_literal: true

module Ai
  module Office
    module Tools
      # Changes a breath card in place instead of drafting a new one: its
      # words, room or image. A breath already posted (or scheduled) is
      # changed on the live post too, since the founder asked for it.
      class UpdateBreath < Base
        def self.definition
          {
            name: "update_breath",
            description: "Change an existing breath card in this conversation, in place: its text, title, room, prayer flag or image. " \
                         "Use this (not draft_breath) whenever the founder wants a breath changed or a flyer added to it. " \
                         "breath_id comes from draft_breath results or Office notes. flyer_id attaches an image from generate_flyer (replacing any image already there); remove_flyer takes it off. " \
                         "If the breath is already posted or scheduled, the live post is updated straight away (its other images are kept).",
            parameters: {
              type: "object",
              properties: {
                breath_id: { type: "integer", description: "The breath card's id." },
                title: { type: "string", description: "New title (empty string removes it)." },
                body: { type: "string", description: "New breath text, in full. Plain text; blank lines between paragraphs." },
                room: { type: "string", description: "Room name, or empty for the main feed." },
                prayer_request: { type: "boolean", description: "Drafts only: true if this is a prayer request." },
                flyer_id: { type: "integer", description: "flyer_id of an image in this conversation to show with the breath." },
                remove_flyer: { type: "boolean", description: "True to take the image off the breath." }
              },
              required: [ "breath_id" ]
            }
          }
        end

        def call
          message = find_breath(input["breath_id"])
          return Outcome.error("breath_id #{input['breath_id']} isn't a breath card in this conversation.") unless message

          changes = {}
          changes["title"] = input["title"].to_s.strip.truncate(200) if input.key?("title")
          changes["body"] = input["body"].to_s.strip if input["body"].present?
          if input.key?("room")
            room = find_room(input["room"])
            return Outcome.error("There's no room called #{input['room']}.") if input["room"].present? && !room

            changes["room_id"] = room&.id
          end
          changes["prayer"] = input["prayer_request"] == true if input.key?("prayer_request")
          if input["flyer_id"].present?
            image = find_image(input["flyer_id"])
            return Outcome.error("flyer_id #{input['flyer_id']} isn't an image in this conversation.") unless image

            changes["image_message_id"] = image.id
          elsif input["remove_flyer"] == true
            changes["image_message_id"] = nil
          end
          return Outcome.error("Nothing to change: pass body, title, room, prayer_request, flyer_id or remove_flyer.") if changes.empty?

          editor = BreathCard.new(message, admin: user)
          changes.delete("prayer") if editor.live? # a live post's prayer status belongs to the prayer flow
          result = editor.update(changes)
          return Outcome.error(result.errors.to_sentence) unless result.ok?

          card = message.reload.card_data
          Outcome.new(result: {
            "status" => editor.live? ? "live_post_updated" : "card_updated", "breath_id" => message.id,
            "card_status" => card["status"], "flyer_id" => card["image_message_id"],
            "post_url" => (routes.post_path(card["post_slug"].presence || card["post_id"]) if editor.live?),
            "changed" => changes.keys.map { |k| k == "image_message_id" ? "image" : k.delete_suffix("_id") }
          }.compact)
        end
      end
    end
  end
end
