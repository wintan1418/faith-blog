# frozen_string_literal: true

# Send the founder's welcome note to members who joined before it existed.
#   bin/rails welcome:existing            # count only
#   bin/rails welcome:existing SEND=1     # send
namespace :welcome do
  desc "Send the welcome note to existing members who haven't had it"
  task existing: :environment do
    members = User.where(active: true, welcomed_at: nil)
    sender = WelcomeNote.sender
    puts "From: #{sender&.username || 'nobody (no admin found)'}. #{members.count} members haven't had the welcome note."
    next unless ENV["SEND"] == "1"

    members.find_each { |user| WelcomeNoteJob.perform_later(user, existing: true) }
    puts "Queued #{members.count} welcome notes."
  end
end
