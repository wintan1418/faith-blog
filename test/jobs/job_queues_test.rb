# frozen_string_literal: true

require "test_helper"

# Every job must land on a queue some worker in config/queue.yml polls,
# or it would sit in solid_queue_ready_executions forever.
class JobQueuesTest < ActiveSupport::TestCase
  EXPECTED = {
    "realtime"   => %w[PushNotificationJob MessageModerationJob],
    "moderation" => %w[AiModerationGateJob AiModerationReviewJob AvatarModerationJob PortfolioModerationJob ModerationBacklogSweepJob],
    "default"    => %w[BadgeCheckJob WelcomeNoteJob ErrorAlertJob AppleTokenRevokeJob ScheduledPostPublisherJob SiteHealthCheckJob OfficeReplyJob
                       IndexNowFlushJob SearchConsoleRefreshJob],
    "bulk"       => %w[WeeklyDigestFanoutJob BroadcastFanoutJob BotsRefreshJob BibleQuizWarmPoolJob BibleQuizTopUpJob
                       AnalyticsCleanupJob BreathFanoutJob BirthdayNotificationsJob AppUpdateReminderJob
                       SearchIndexingNightlyJob ScriptureInsightJob]
  }.freeze

  def polled_queues
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/queue.yml"))
    config.fetch("production").fetch("workers").flat_map { |w| Array(w["queues"]) }
  end

  test "jobs are on their named queues" do
    EXPECTED.each do |queue, jobs|
      jobs.each { |job| assert_equal queue, job.constantize.new.queue_name, "#{job} should be on #{queue}" }
    end
  end

  test "every job, mailer, push and broadcast queue has a production worker" do
    Rails.application.eager_load!
    queues = polled_queues
    assert_equal queues.uniq, queues, "a queue is polled by two worker blocks"
    refute_includes queues, "*"

    jobs = ApplicationJob.descendants + [ ApplicationPushNotificationJob ]
    jobs.each { |job| assert_includes queues, job.new.queue_name, "#{job} is on an unpolled queue" }

    assert_includes queues, ApplicationPushNotification.queue_name.to_s
    assert_equal "realtime", ApplicationPushNotification.queue_name.to_s
    assert_equal "mailers", ActionMailer::Base.deliver_later_queue_name.to_s
    assert_includes queues, "mailers"
    [ Turbo::Streams::BroadcastJob, Turbo::Streams::BroadcastStreamJob, Turbo::Streams::ActionBroadcastJob ].each do |job|
      assert_equal "realtime", job.new.queue_name
    end
    [ ActiveStorage::AnalyzeJob, ActiveStorage::PurgeJob ].each do |job|
      assert_includes queues, job.new.queue_name
    end
  end

  test "recurring tasks use their job's own queue" do
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
    config.fetch("production").each_value do |task|
      refute task.key?("queue"), "recurring task pins a queue: #{task.inspect}"
    end
  end
end
