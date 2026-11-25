# frozen_string_literal: true

require "test_helper"

class FeedbackCampaignTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @member = create_member("fb_member", created_at: 20.days.ago, last_seen_at: 1.hour.ago)
  end

  def campaign(**attrs)
    FeedbackCampaign.create!({ title: "How is Brethreign working for you?" }.merge(attrs))
  end

  def answer(campaign, user, rating)
    campaign.responses.create!(user: user).submit!(rating: rating)
  end

  test "a draft launches now and becomes live" do
    c = campaign
    assert_equal "draft", c.status
    assert_enqueued_with(job: FeedbackCampaignDeliveryJob) { assert c.launch! }
    assert c.live?
    assert_not c.launch!, "launches once"
  end

  test "a future start is scheduled, not live" do
    c = campaign(starts_at: 2.days.from_now, ends_at: 5.days.from_now)
    c.launch!
    assert_equal "scheduled", c.status
    assert_not FeedbackCampaign.live.exists?(c.id)
  end

  test "closing ends it and quietens its alerts" do
    c = campaign
    c.launch!
    Notification.create!(user: @member, notifiable: c, notification_type: :feedback_request)
    c.close!
    assert_equal "closed", c.status
    assert_equal 0, @member.notifications.unread.where(notifiable: c).count
  end

  test "multiple choice needs a question and two answers" do
    c = FeedbackCampaign.new(title: "Hi", choice_question: "What do you use most?", choice_options: [ "Feed" ])
    assert_not c.valid?
    c.choice_options = [ "Feed", " Rooms ", "" ]
    assert c.valid?
    assert_equal %w[Feed Rooms], c.choice_options
  end

  test "audiences" do
    fresh = create_member("fb_fresh", created_at: 2.days.ago, last_seen_at: 1.day.ago)
    sleepy = create_member("fb_sleepy", created_at: 90.days.ago, last_seen_at: 60.days.ago)
    Ahoy::Visit.create!(visit_token: SecureRandom.hex, visitor_token: SecureRandom.hex, user_id: sleepy.id, platform: "android_app", started_at: 3.days.ago)

    assert_includes campaign(audience: :everyone).audience_scope, sleepy
    assert_not_includes campaign(audience: :active_recently).audience_scope, sleepy
    assert_equal [ fresh.id ], campaign(audience: :new_members).audience_scope.where(id: [ fresh, sleepy, @member ]).pluck(:id)
    assert_equal [ sleepy.id ], campaign(audience: :android_app).audience_scope.pluck(:id)
    assert_empty campaign(audience: :ios_app).audience_scope

    @member.dismiss_card!(FeedbackCampaign::OPT_OUT_KEY)
    assert_not_includes campaign.audience_scope, @member, "opted out of surveys"
  end

  test "the pop-up: one live survey, never on the first day, and it respects Not now / Don't ask again" do
    c = campaign
    c.launch!
    assert_equal c, FeedbackCampaign.prompt_for(@member)

    newbie = create_member("fb_newbie")
    assert_nil FeedbackCampaign.prompt_for(newbie), "not on their first day"

    response = c.responses.create!(user: @member)
    response.snooze!
    assert_nil FeedbackCampaign.prompt_for(@member)
    travel 2.days + 1.minute do
      assert_equal c, FeedbackCampaign.prompt_for(@member)
      response.snooze!
      response.update!(snoozed_until: 1.minute.ago)
      response.snooze!
      response.update!(snoozed_until: 1.minute.ago)
      assert_equal 3, response.snooze_count
      assert_nil FeedbackCampaign.prompt_for(@member), "three snoozes and it stops asking"
    end

    other = create_member("fb_other", created_at: 5.days.ago)
    c.responses.create!(user: other).decline!
    assert_nil FeedbackCampaign.prompt_for(other)
  end

  test "an answer is saved once, in range, and earns seeds" do
    c = campaign(rating_kind: :nps)
    c.launch!
    response = c.responses.create!(user: @member)
    assert_not response.submit!(rating: 11)
    response.reload
    assert response.submit!(rating: 9, comment: "  Love the Bible reader ", platform: "android_app")
    assert_equal "Love the Bible reader", response.comment
    assert_equal 1, c.reload.responses_count
    assert_not response.submit!(rating: 2), "one answer per member"
    assert SeedEvent.exists?(user_id: @member.id, kind: "feedback")
    assert_nil FeedbackCampaign.prompt_for(@member)
  end

  test "results: NPS, average and distribution" do
    c = campaign(rating_kind: :nps)
    c.launch!
    [ 10, 9, 7, 3 ].each_with_index { |r, i| answer(c, create_member("fb_r#{i}"), r) }

    assert_equal 25, c.nps_score # 2 promoters, 1 detractor, 1 passive: (2 - 1) / 4
    assert_equal 7.25, c.average_rating
    assert_equal 1, c.distribution[10]
    assert_equal 0, c.distribution[0]
    assert_equal 11, c.distribution.size
  end

  test "one survey at a time: after answering one, the next waits a week" do
    first = campaign
    first.launch!
    second = campaign(title: "How likely are you to recommend Brethreign?", rating_kind: :nps)
    second.launch!
    shown = FeedbackCampaign.prompt_for(@member)
    shown.responses.create!(user: @member).submit!(rating: shown.rating_range.max)

    assert_nil FeedbackCampaign.prompt_for(@member)
    travel FeedbackCampaign::REST_BETWEEN_SURVEYS + 1.hour do
      assert_equal ([ first, second ] - [ shown ]).first, FeedbackCampaign.prompt_for(@member)
    end
  end
end
