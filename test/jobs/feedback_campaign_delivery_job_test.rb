# frozen_string_literal: true

require "test_helper"

class FeedbackCampaignDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @a = create_member("fbd_a", created_at: 10.days.ago)
    @b = create_member("fbd_b", created_at: 10.days.ago)
    @campaign = FeedbackCampaign.create!(title: "How is Brethreign working for you?", launched_at: Time.current, starts_at: 1.minute.ago)
  end

  test "one alert per member, no email and no push unless asked, and only once" do
    assert_no_enqueued_jobs(only: PushNotificationJob) do
      assert_no_enqueued_emails do
        FeedbackCampaignDeliveryJob.perform_now(@campaign.id)
      end
    end

    assert_equal 1, @a.notifications.feedback_request.where(notifiable: @campaign).count
    assert_equal 1, @b.notifications.feedback_request.where(notifiable: @campaign).count
    assert_equal User.active.count, @campaign.reload.targeted_count
    assert @campaign.delivered_at

    assert_no_difference("Notification.count") { FeedbackCampaignDeliveryJob.perform_now(@campaign.id) }

    alert = @a.notifications.feedback_request.first
    assert_match "We'd love your feedback", alert.web_message
    assert_equal "/feedback/#{@campaign.id}", alert.target_path
  end

  test "pushes when the admin ticked it (and push is set up)" do
    @campaign.update!(also_push: true)
    WebPushConfig.stub(:configured?, true) do
      assert_enqueued_jobs(User.active.count, only: PushNotificationJob) do
        FeedbackCampaignDeliveryJob.perform_now(@campaign.id)
      end
    end
  end

  test "skips drafts, closed surveys and ones that haven't started" do
    draft = FeedbackCampaign.create!(title: "Draft")
    later = FeedbackCampaign.create!(title: "Later", launched_at: Time.current, starts_at: 1.day.from_now)
    closed = FeedbackCampaign.create!(title: "Closed", launched_at: Time.current, starts_at: 1.hour.ago, closed_at: Time.current)

    assert_no_difference("Notification.count") do
      [ draft, later, closed ].each { |c| FeedbackCampaignDeliveryJob.perform_now(c.id) }
    end
  end
end
