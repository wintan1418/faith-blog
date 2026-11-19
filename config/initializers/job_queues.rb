# frozen_string_literal: true

# Turbo's broadcast jobs (live feed, chat, Office replies) belong with the
# other realtime work, not behind bulk jobs on "default". See config/queue.yml.
Rails.application.config.after_initialize do
  [ Turbo::Streams::BroadcastJob, Turbo::Streams::BroadcastStreamJob, Turbo::Streams::ActionBroadcastJob ].each do |job|
    job.queue_as :realtime
  end
end
