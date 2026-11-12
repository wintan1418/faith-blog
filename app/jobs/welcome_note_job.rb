# frozen_string_literal: true

class WelcomeNoteJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(user, existing: false)
    WelcomeNote.deliver(user, existing: existing)
  end
end
