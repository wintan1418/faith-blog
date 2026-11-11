# frozen_string_literal: true

module Ai
  module Office
    module Tools
      # Announcements go live the moment they're saved, so this only prepares
      # a card; the founder publishes it from there.
      class DraftAnnouncement < Base
        def self.definition
          {
            name: "draft_announcement",
            description: "Prepare an in-app announcement as a card the founder can publish. kind 'release' shows as a \"What's new\" slide set: " \
                         "one feature per line of body, like \"🎂 Birthdays — Celebrate your brethren on their day\". kind 'custom' is a single notice.",
            parameters: {
              type: "object",
              properties: {
                title: { type: "string", description: "Headline, under 160 characters." },
                kicker: { type: "string", description: "Short label above the title, e.g. \"Just shipped\" (under 80 characters)." },
                body: { type: "string", description: "Body text. For release: one feature per line." },
                kind: { type: "string", enum: %w[release custom] }
              },
              required: %w[title body]
            }
          }
        end

        def call
          title = input["title"].to_s.strip
          return Outcome.error("The announcement needs a title.") if title.blank?

          card = {
            "kind" => "announcement", "status" => "draft",
            "title" => title.truncate(160),
            "kicker" => input["kicker"].to_s.strip.truncate(80),
            "body" => input["body"].to_s.strip,
            "announcement_kind" => input["kind"].to_s.in?(%w[release custom]) ? input["kind"].to_s : "release"
          }
          Outcome.new(result: { "status" => "card_shown", "note" => "Not published yet; the founder publishes it from the card." }, card: card)
        end
      end
    end
  end
end
