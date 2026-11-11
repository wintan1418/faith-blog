# frozen_string_literal: true

module Ai
  module Office
    module Providers
      # No network: used in tests and when no AI key is configured. Picks a
      # tool from keywords in the founder's last message so every card can be
      # tried locally. Tests can queue exact replies with Stub.script.
      class Stub < Base
        DEFAULT_MODEL = "stub"

        class_attribute :scripted, default: []

        # Queue replies (Reply objects) the next chat calls return, in order.
        def self.script(*replies) = self.scripted = replies.flatten
        def self.reset! = self.scripted = []

        def display_name = "Stub (no AI key)"

        def chat(system:, messages:, tools:) # rubocop:disable Lint/UnusedMethodArgument
          if scripted.any?
            reply, *rest = scripted
            self.class.scripted = rest
            return reply
          end

          last = messages.last || {}
          return summary_after_tools(messages) if last[:role] == :tool

          route(last[:text].to_s)
        end

        private

        def route(text)
          down = text.downcase
          if down.match?(/how many|stats|numbers|signed up|sign-ups|signups/)
            call("site_stats", { "days" => 7 })
          elsif down.include?("flyer") || down.include?("image") || down.include?("poster")
            call("generate_flyer", { "brief" => text.truncate(300), "size" => "square", "text_on_image" => "Keep breathing" })
          elsif down.match?(/email|mail|newsletter/)
            call("draft_email", {
              "subject" => "A note from Brethreign",
              "preheader" => "Thank you for breathing with us",
              "body_html" => "<p>Dear friend,</p><p>Thank you for being part of Brethreign. #{ERB::Util.h(text.truncate(200))}</p><p>Yours faithfully,<br>The Brethreign team</p>"
            })
          elsif down.include?("announce")
            call("draft_announcement", { "title" => "Something new on Brethreign", "kicker" => "Just shipped", "body" => "✨ #{text.truncate(120)}" })
          elsif down.match?(/breath|post /)
            call("draft_breath", { "body" => "Grace for today: #{text.truncate(200)}", "title" => "" })
          elsif down.match?(/recent|latest|activity|reports/)
            call("recent_activity", { "kind" => down.include?("report") ? "reports" : "posts", "limit" => 5 })
          else
            Reply.new(text: "**Stub reply.** No AI key is configured here, so this is a canned answer.\n\nYou said:\n\n> #{text.truncate(400)}\n\nTry asking for a *breath*, a *flyer*, an *email*, an *announcement* or *stats*.",
                      model: "stub", stop_reason: "end_turn")
          end
        end

        def call(name, input)
          Reply.new(text: "On it — using `#{name}`.", tool_calls: [ { "id" => "stub_#{SecureRandom.hex(4)}", "name" => name, "input" => input } ],
                    model: "stub", stop_reason: "tool_use")
        end

        def summary_after_tools(messages)
          names = messages.reverse.take_while { |m| m[:role] == :tool }.map { |m| m[:name] }
          Reply.new(text: "Done (#{names.reverse.join(', ')}). The card above has the details and buttons.", model: "stub", stop_reason: "end_turn")
        end
      end
    end
  end
end
