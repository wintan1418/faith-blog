# frozen_string_literal: true

# Re-evaluates a user's badges after activity (post, comment, reaction,
# game). Cheap idempotent count checks; awards + notifies anything new.
class BadgeCheckJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(user_id)
    UserBadge.check!(User.find_by(id: user_id))
  end
end
