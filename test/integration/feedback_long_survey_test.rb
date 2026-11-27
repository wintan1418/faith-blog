# frozen_string_literal: true

require "test_helper"

class FeedbackLongSurveyTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  QUESTIONS = <<~TEXT
    # one: Where do you live?
    Nigeria
    United Kingdom
    United States

    # many 2: What should we build next?
    > Pick up to 2.
    Job board
    Calls
    Live streams

    # text: What do you love most?

    # rating: How likely are you to recommend Brethreign to a friend?

    # one optional: Can we reach out to you?
    Yes
    No
  TEXT

  setup do
    @member = create_member("fls_member", created_at: 10.days.ago)
    @admin = create_member("fls_admin", role: :admin, created_at: 30.days.ago)
    @campaign = FeedbackCampaign.create!(title: "Help us build your home", rating_kind: "nps",
                                         follow_up_prompt: "Tell us honestly.", questions_text: QUESTIONS)
  end

  test "questions written as text are parsed, keyed in order and written back the same way" do
    q = @campaign.questions
    assert_equal %w[q1 q2 q3 rating q4], q.map { |x| x["key"] }
    assert_equal %w[one many text rating one], q.map { |x| x["kind"] }
    assert_equal 2, q[1]["max"]
    assert_equal "Pick up to 2.", q[1]["hint"]
    assert q[4]["optional"]
    assert_equal 5, @campaign.question_count
    assert_equal "about 1 minute", @campaign.duration_label

    again = FeedbackCampaign.new(title: "x", questions_text: @campaign.questions_text)
    assert again.valid?
    assert_equal @campaign.questions, again.tap(&:valid?).questions
  end

  test "badly written questions are refused with a clear reason" do
    bad = FeedbackCampaign.new(title: "x", questions_text: "Where do you live?\n# one: Pick\nOnly one")
    assert_not bad.valid?
    assert_match "start each question", bad.errors[:questions].join
    assert_match "at least two answers", bad.errors[:questions].join
  end

  test "an admin previews a draft; members can't open it" do
    sign_in @member
    get feedback_survey_path(@campaign)
    assert_redirected_to feed_path

    sign_in @admin
    get feedback_survey_path(@campaign)
    assert_response :success
    assert_select ".fb-preview"
    assert_select "fieldset.fb-q", 5
    post feedback_survey_path(@campaign), params: { feedback: { rating: 9, answers: { q1: "Nigeria", q2: [ "Calls" ] } } }
    assert_redirected_to feedback_survey_path(@campaign)
    assert_equal 0, @campaign.responses.count, "a preview saves nothing"
  end

  test "the page shows every question, and a full answer is saved" do
    @campaign.launch!
    sign_in @member
    get feedback_survey_path(@campaign)
    assert_select "h1.fb-long-title", text: "Help us build your home"
    assert_select "input[type=radio][name='feedback[answers][q1]']", 3
    assert_select ".fb-chip-row[data-max='2'] input[type=checkbox][name='feedback[answers][q2][]']", 3
    assert_select "textarea[name='feedback[answers][q3]']"
    assert_select "input[type=radio][name='feedback[rating]']", 11

    post feedback_survey_path(@campaign), params: { feedback: { rating: 10, answers: {
      q1: "United Kingdom", q2: [ "Job board", "Calls" ], q3: "  The kindness  ", q4: "Yes", sneaky: "x" } } }
    assert_redirected_to feedback_survey_path(@campaign)

    answer = @campaign.responses.find_by(user: @member)
    assert_equal 10, answer.rating
    assert_equal({ "q1" => "United Kingdom", "q2" => [ "Job board", "Calls" ], "q3" => "The kindness", "q4" => "Yes" }, answer.answers)
  end

  test "a missing required answer, too many picks or an answer not on the list is refused" do
    @campaign.launch!
    sign_in @member

    post feedback_survey_path(@campaign), params: { feedback: { rating: 7, answers: { q2: [ "Calls" ] } } }
    assert_response :unprocessable_entity
    assert_match "Please answer question 1", response.body
    assert_select "fieldset.fb-q", 5, "the long form comes back, not the short one"

    post feedback_survey_path(@campaign), params: { context: "page", feedback: { rating: 7, answers: { q2: [ "Calls" ] } } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "fb-q-num", response.body
    assert_match "Calls", response.body

    post feedback_survey_path(@campaign), params: { feedback: { rating: 7, answers: { q1: "Nigeria", q2: [ "Job board", "Calls", "Live streams" ] } } }
    assert_response :unprocessable_entity
    assert_match "up to 2 picks", response.body

    post feedback_survey_path(@campaign), params: { feedback: { rating: 7, answers: { q1: "Mars", q2: [ "Calls" ] } } }
    assert_response :unprocessable_entity
    assert_nil @campaign.responses.find_by(user: @member)&.submitted_at

    # Optional and text questions may be skipped.
    post feedback_survey_path(@campaign), params: { feedback: { rating: 7, answers: { q1: "Nigeria", q2: [ "Calls" ] } } }
    assert_redirected_to feedback_survey_path(@campaign)
  end

  test "the feed pop-up invites them to the survey page instead of showing every question" do
    @campaign.launch!
    sign_in @member
    get feed_path
    assert_select "aside.fb-sheet" do
      assert_select "a[href=?]", feedback_survey_path(@campaign), text: "Take the survey"
      assert_select "input[name='feedback[rating]']", 0
      assert_select "button[data-action='feedback#never']"
    end
  end

  test "launching with also email sends each member one email with the survey link" do
    @campaign.update!(also_email: true)
    quiet = create_member("fls_quiet", created_at: 10.days.ago)
    quiet.update_columns(email_notifications_enabled: false)
    @campaign.launch!

    perform_enqueued_jobs(only: FeedbackCampaignDeliveryJob)
    enqueued = enqueued_jobs.select { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" && j["arguments"].first == "FeedbackMailer" }
    recipients = enqueued.map { |j| j["arguments"].last["params"]["user"]["_aj_globalid"] }
    assert_includes recipients, @member.to_global_id.to_s
    assert_not_includes recipients, quiet.to_global_id.to_s

    mail = FeedbackMailer.with(campaign: @campaign, user: @member).survey
    assert_equal [ @member.email ], mail.to
    assert_match "Help us build your home", mail.subject
    assert_match "/feedback/#{@campaign.id}", mail.html_part.body.to_s
    assert_match "Unsubscribe", mail.text_part.body.to_s
  end

  test "admin results count each answer and the CSV has a column per question" do
    @campaign.launch!
    @campaign.responses.create!(user: @member).submit!(rating: 9, answers: { "q1" => "Nigeria", "q2" => [ "Calls", "Job board" ], "q3" => "Peace" })

    sign_in @admin
    get admin_feedback_campaign_path(@campaign)
    assert_response :success
    assert_match "Where do you live?", response.body
    assert_match "Peace", response.body

    assert_equal 1, @campaign.question_counts(@campaign.questions.first)["Nigeria"]
    get admin_feedback_campaign_path(@campaign, format: :csv)
    csv = CSV.parse(response.body)
    assert_includes csv.first, "What should we build next?"
    assert_includes csv.last, "Calls, Job board"
  end
end
