# frozen_string_literal: true

# Admin → App versions: the newest Android version on Google Play, the oldest one
# still allowed in, which versions members use, and a reminder for those behind.
class Admin::AppReleasesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_release
  layout "admin"

  def edit
    load_stats
  end

  def update
    if @release.update(release_params)
      redirect_to edit_admin_app_release_path, notice: "App versions saved."
    else
      load_stats
      render :edit, status: :unprocessable_entity
    end
  end

  def remind
    if @release.persisted? && @release.latest
      AppUpdateReminderJob.perform_later(@release.id)
      @release.update_column(:reminded_at, Time.current)
      redirect_to edit_admin_app_release_path, notice: "Sending an update reminder to members on an older version."
    else
      redirect_to edit_admin_app_release_path, alert: "Save the latest version first."
    end
  end

  private

  def set_release
    @release = AppRelease.android
  end

  def load_stats
    @version_counts = AppRelease.android_version_counts
    @outdated_count = @release.persisted? ? @release.outdated_users.count : 0
  end

  def release_params
    params.require(:app_release).permit(:latest_version, :minimum_version)
  end
end
