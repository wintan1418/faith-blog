# frozen_string_literal: true

require "test_helper"
require_relative "../support/sweep_world"

# Every background job run for real (perform_now, and whatever it enqueues
# run too) against a full world of records, with the arguments the app
# really passes. A job that crashes in production fails silently for members:
# no alerts, no moderation, no digest. Jobs that only talk to outside services
# (Apple token revoke, the Updates bots' feeds) are left out.
class JobSweepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SweepWorld

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    build_sweep_world
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def run_job(job_class, *args, **kwargs)
    perform_enqueued_jobs(except: [ AppleTokenRevokeJob, BotsRefreshJob ]) do
      job_class.perform_now(*args, **kwargs)
    end
  rescue StandardError => e
    flunk "#{job_class.name} crashed: #{e.class}: #{e.message}\n#{e.backtrace.grep(%r{/app/}).first(5).join("\n")}"
  end

  test "moderation jobs" do
    run_job(AiModerationGateJob, @held.id)
    run_job(AiModerationGateJob, @post.id, recheck: true)
    run_job(AiModerationReviewJob, @post)
    run_job(AiModerationReviewJob, @comment)
    run_job(MessageModerationJob, @message)
    run_job(MessageModerationJob, @message, notify: false)
    run_job(PortfolioModerationJob, @portfolio_item)
    @member.profile.avatar.attach(png_blob("face.png"))
    run_job(AvatarModerationJob, @member.profile)
    run_job(ModerationBacklogSweepJob)
  end

  test "fan-out, digest, birthdays, scheduled posts, badges, welcome notes" do
    run_job(BreathFanoutJob, @post.id)
    run_job(BreathFanoutJob, 0)
    run_job(BroadcastFanoutJob, @broadcast)
    run_job(WeeklyDigestFanoutJob)
    @other.profile.update!(birth_month: Date.current.month, birth_day: Date.current.day, show_birthday: true)
    run_job(BirthdayNotificationsJob)
    @scheduled.update_columns(scheduled_for: 1.minute.ago)
    run_job(ScheduledPostPublisherJob)
    assert @scheduled.reload.published?
    run_job(BadgeCheckJob, @member.id)
    run_job(BadgeCheckJob, 0)
    run_job(WelcomeNoteJob, @member)
    run_job(WelcomeNoteJob, @other, existing: true)
  end

  test "notifications and pushes" do
    @member.notifications.find_each { |n| run_job(PushNotificationJob, n) }
    release = AppRelease.create!(platform: "android", latest_version: "9.9.9", minimum_version: "1.0.0")
    run_job(AppUpdateReminderJob, release.id)
  end

  test "housekeeping, quiz pool, office, error alerts, health check" do
    run_job(AnalyticsCleanupJob)
    run_job(BibleQuizWarmPoolJob)
    run_job(BibleQuizTopUpJob)
    @office_conversation.messages.create!(role: 0, content: "Draft a breath about rest.")
    run_job(OfficeReplyJob, @office_conversation.id)
    run_job(ErrorAlertJob, "Something broke", "detail", 3)
    run_job(SiteHealthCheckJob)
  end
end
