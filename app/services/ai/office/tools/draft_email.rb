# frozen_string_literal: true

module Ai
  module Office
    module Tools
      # Saves a Broadcast as a DRAFT. Sending stays on the Broadcasts page,
      # behind its own confirm step; nothing here can send mail.
      class DraftEmail < Base
        def self.definition
          {
            name: "draft_email",
            description: "Save an email to all members as a DRAFT broadcast. It is never sent from here: the founder reviews and sends it on the Broadcasts page.",
            parameters: {
              type: "object",
              properties: {
                subject: { type: "string", description: "Subject line, under 80 characters." },
                preheader: { type: "string", description: "Preview text shown after the subject, under 120 characters." },
                body_html: { type: "string", description: "The email body as simple HTML (<p>, <h2>, <ul>, <li>, <strong>, <em>, <a>), ending with the founder's sign-off." }
              },
              required: %w[subject body_html]
            }
          }
        end

        def call
          broadcast = Broadcast.new(
            sender: user,
            subject: input["subject"].to_s.strip.truncate(200),
            preheader: input["preheader"].to_s.strip.truncate(200),
            body: input["body_html"].to_s,
            status: :draft
          )
          return Outcome.error("Couldn't save the draft: #{broadcast.errors.full_messages.to_sentence}") unless broadcast.save

          recipients = Broadcast.eligible_user_count
          Outcome.new(
            result: { "status" => "draft_saved_not_sent", "broadcast_id" => broadcast.id, "eligible_recipients" => recipients,
                      "note" => "The founder reviews and sends it on the Broadcasts page." },
            card: { "kind" => "email", "broadcast_id" => broadcast.id, "subject" => broadcast.subject,
                    "preheader" => broadcast.preheader, "recipients" => recipients }
          )
        end
      end
    end
  end
end
