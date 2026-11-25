# frozen_string_literal: true

require "test_helper"

class FeedbackSurveysTest < ActionDispatch::IntegrationTest
  setup do
    @member = create_member("fbi_member", created_at: 10.days.ago)
    @admin = create_member("fbi_admin", role: :admin, created_at: 30.days.ago)
    @campaign = FeedbackCampaign.create!(title: "How is Brethreign working for you?", follow_up_prompt: "What should we improve?",
                                         choice_question: "What do you use most?", choice_options: %w[Feed Rooms Bible])
    @campaign.launch!
  end

  test "the feed shows the pop-up with the rating, text box, Not now and Don't ask again" do
    sign_in @member
    get feed_path
    assert_select "aside.fb-sheet[data-controller=feedback][data-feedback-prompt-value=true]" do
      assert_select "input[type=radio][name='feedback[rating]']", 5
      assert_select "textarea[name='feedback[comment]']"
      assert_select "input[name='feedback[choice]']", 3
      assert_select "button[data-action='feedback#later']", text: "Not now"
      assert_select "button[data-action='feedback#never']", text: "Don't ask again"
    end
  end

  test "no pop-up on a member's first day" do
    sign_in create_member("fbi_new")
    get feed_path
    assert_select "aside.fb-sheet", 0
  end

  test "answering from the pop-up thanks them, pays seeds and stops the pop-up" do
    sign_in @member
    post feedback_survey_path(@campaign), params: { context: "sheet", feedback: { rating: 4, comment: "More rooms please", choice: "Rooms" } },
                                          as: :turbo_stream
    assert_response :success
    assert_match "Thank you", response.body
    assert_match "+5 seeds", response.body

    answer = @campaign.responses.find_by(user: @member)
    assert_equal [ 4, "More rooms please", "Rooms", "web" ], [ answer.rating, answer.comment, answer.choice, answer.platform ]

    post feedback_survey_path(@campaign), params: { feedback: { rating: 1 } }, as: :turbo_stream
    assert_equal 4, answer.reload.rating, "one answer per member"

    get feed_path
    assert_select "aside.fb-sheet", 0
  end

  test "the alert's survey page, from the app, records the platform" do
    sign_in @member
    get feedback_survey_path(@campaign)
    assert_response :success
    assert_select "form .fb-scale"

    post feedback_survey_path(@campaign), params: { feedback: { rating: 5 } },
                                          headers: { "User-Agent" => "Brethreign/1.2 (iPhone) Hotwire Native iOS" }
    assert_redirected_to feedback_survey_path(@campaign)
    assert_equal "ios_app", @campaign.responses.find_by(user: @member).platform
    follow_redirect!
    assert_select ".fb-thanks"
  end

  test "Not now and Don't ask again" do
    sign_in @member
    post snooze_feedback_survey_path(@campaign)
    assert_response :no_content
    assert_equal 1, @campaign.responses.find_by(user: @member).snooze_count

    post decline_feedback_survey_path(@campaign)
    assert @campaign.responses.find_by(user: @member).declined?
  end

  test "a closed survey takes no more answers" do
    @campaign.close!
    sign_in @member
    post feedback_survey_path(@campaign), params: { feedback: { rating: 5 } }
    assert_redirected_to feedback_survey_path(@campaign)
    assert_not @campaign.responses.submitted.exists?
  end

  test "members can turn surveys off in notification settings" do
    sign_in @member
    patch settings_notifications_path, params: { feedback_surveys: "0", email_notifications_enabled: "1" }
    assert @member.reload.card_dismissed?(FeedbackCampaign::OPT_OUT_KEY)
    get feed_path
    assert_select "aside.fb-sheet", 0

    patch settings_notifications_path, params: { feedback_surveys: "1", email_notifications_enabled: "1" }
    assert_not @member.reload.card_dismissed?(FeedbackCampaign::OPT_OUT_KEY)
  end

  # ── Admin ──

  test "only admins see Admin → Feedback" do
    sign_in @member
    get admin_feedback_campaigns_path
    assert_response :redirect
  end

  test "an admin writes, launches and reads a survey" do
    sign_in @admin
    get new_admin_feedback_campaign_path
    assert_response :success

    assert_difference("FeedbackCampaign.count") do
      post admin_feedback_campaigns_path, params: { feedback_campaign: {
        title: "How likely are you to recommend Brethreign?", rating_kind: "nps", follow_up_prompt: "Why?",
        choice_question: "", choice_options_text: "", audience: "active_recently", also_push: "0",
        starts_at: "", ends_at: 7.days.from_now.strftime("%Y-%m-%dT%H:%M")
      } }
    end
    survey = FeedbackCampaign.order(:id).last
    assert survey.draft?
    assert survey.rating_nps?

    assert_enqueued_with(job: FeedbackCampaignDeliveryJob) { post launch_admin_feedback_campaign_path(survey) }
    assert survey.reload.live?

    survey.responses.create!(user: @member).submit!(rating: 10, comment: "=SUM(A1)", platform: "android_app")
    survey.responses.create!(user: create_member("fbi_two")).submit!(rating: 3, comment: "Slow on my phone")

    get admin_feedback_campaign_path(survey)
    assert_response :success
    assert_select ".afb-stat-value", text: "+0"
    assert_select ".afb-answer", 2
    assert_select "a[href=?]", user_path(@member.username)

    get admin_feedback_campaign_path(survey, rating: 3)
    assert_select ".afb-answer", 1
    assert_select ".afb-answer-comment", text: "Slow on my phone"

    get admin_feedback_campaign_path(survey, format: :csv)
    assert_equal "text/csv", response.media_type
    assert_match "'=SUM(A1)", response.body
    assert_match "Android app", response.body

    post close_admin_feedback_campaign_path(survey)
    assert survey.reload.closed?
  end
end
