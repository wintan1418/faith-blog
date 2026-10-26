# frozen_string_literal: true

# Remembers that someone has seen a "What's new" release, so it shows only once.
class WhatsNewController < ApplicationController
  before_action :authenticate_user!

  def seen
    release = Announcement.releases.find(params[:id])
    current_user.update_column(:seen_release_id, release.id) if current_user.seen_release_id.to_i < release.id
    head :no_content
  end
end
