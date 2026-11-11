# frozen_string_literal: true

# Writes the Office assistant's reply in the background so long answers and
# slow tools (flyers take up to a minute) never time out the request. The
# reply reaches the page through Turbo Streams as each message is saved.
# Never retried: a retry would repeat tool calls.
class OfficeReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = OfficeConversation.find_by(id: conversation_id)
    return unless conversation

    Ai::Office::Runner.new(conversation).run
  end
end
