# frozen_string_literal: true

require "test_helper"

# Trello #101: players can report a faulty quiz question (not just a wrong
# answer) with a reason and an optional note, and admins see exactly which
# question was reported.
class QuizQuestionReportsTest < ActionDispatch::IntegrationTest
  setup do
    @pass = SecureRandom.base58(16)
    @player = User.create!(username: "qr_player", email: "qr_player@example.com", password: @pass)
    @admin = User.create!(username: "qr_admin", email: "qr_admin@example.com", password: @pass, role: :admin)
    @question = BibleQuizQuestion.create!(
      kind: "what_does", prompt: "In John 19:30, what did Jesus say before he gave up the ghost?",
      choices: [ "It is finished", "Father, forgive them", "I thirst", "Into thy hands" ],
      correct_index: 1, reference: "John 19:30", explanation: "KJV John 19:30",
      theme: "the_cross", difficulty: "easy"
    )
  end

  def report(reason:, note: nil, question: @question)
    post games_quiz_flag_path, params: { question_id: question.id, reason: reason, note: note }.compact, as: :json
  end

  test "a report records the reason and note against the exact question" do
    sign_in @player
    assert_difference -> { Report.count }, 1 do
      report(reason: "wrong_answer", note: "  It should be \"It is finished\" (John 19:30).  ")
    end
    assert_response :success
    assert JSON.parse(response.body)["ok"]

    r = Report.last
    assert_equal @question, r.reportable
    assert_equal @player, r.reporter
    assert r.pending?
    assert_equal 'Quiz question: Wrong answer. Note: It should be "It is finished" (John 19:30).', r.reason
    assert_equal 1, @question.reload.flags_count
  end

  test "every reason is accepted, the note is optional, and an unknown reason counts as a wrong answer" do
    BibleQuizQuestion::REPORT_REASONS.each_key.with_index do |reason, i|
      q = BibleQuizQuestion.create!(kind: "which_book", prompt: "Question #{i} for #{reason}?",
                                    choices: %w[Romans Acts John Jude], correct_index: 0, theme: "faith")
      sign_in @player
      report(reason: reason, question: q)
      assert_response :success
      assert_equal "Quiz question: #{BibleQuizQuestion::REPORT_REASONS[reason]}.", q.reports.last.reason
    end

    sign_in @player
    report(reason: "<script>")
    assert_equal "Quiz question: Wrong answer.", @question.reports.last.reason
  end

  test "reporting again updates the player's report instead of adding a flag" do
    sign_in @player
    report(reason: "unclear")
    sign_in @player
    assert_no_difference -> { Report.count } do
      report(reason: "wrong_reference", note: "Not in Psalms")
    end
    assert_equal "Quiz question: Not in the Bible / wrong reference. Note: Not in Psalms", @question.reports.last.reason
    assert_equal 1, @question.reload.flags_count
  end

  test "an 'other' report goes to admins without counting as a flag" do
    sign_in @player
    report(reason: "other", note: "Typo in the question")
    assert_equal 0, @question.reload.flags_count
    assert_equal 1, @question.reports.pending.count
  end

  test "long notes are trimmed so the report always saves" do
    sign_in @player
    report(reason: "unclear", note: "x" * 2_000)
    assert_response :success
    assert_operator Report.last.reason.length, :<=, 500
  end

  test "signed-out visitors can't report" do
    report(reason: "unclear")
    assert_response :unauthorized
    assert_equal 0, Report.count
  end

  test "the quiz page offers the reasons" do
    sign_in @player
    get games_quiz_path
    assert_response :success
    assert_select "[data-controller=quiz][data-quiz-report-reasons-value]" do |el|
      reasons = JSON.parse(el.first["data-quiz-report-reasons-value"])
      assert_equal %w[wrong_answer unclear wrong_reference off_theme other], reasons.keys
    end
  end

  test "admins see the reported question with its marked answer, and can retire it" do
    sign_in @player
    report(reason: "wrong_answer", note: "Wrong last words")
    r = Report.last

    sign_in @admin
    get admin_reports_path(type: "BibleQuizQuestion")
    assert_response :success
    assert_select "td", text: /Quiz question ##{@question.id}/
    assert_select "td", text: /In John 19:30, what did Jesus say/

    get admin_report_path(r)
    assert_response :success
    assert_select "section[aria-label='Reported question']" do
      assert_select "p", text: @question.prompt
      assert_select "li", text: /Father, forgive them ✓ marked correct/
      assert_select "*", text: /Theme: The cross/
    end
    assert_select "dd", text: "Quiz question: Wrong answer. Note: Wrong last words"

    post retire_question_admin_report_path(r)
    assert_redirected_to admin_reports_path(type: "BibleQuizQuestion")
    assert @question.reload.retired?
    refute_includes BibleQuizQuestion.trusted, @question
    assert r.reload.resolved?
  end

  test "dismissing the last report puts a fine question back in the quiz" do
    other = User.create!(username: "qr_other", email: "qr_other@example.com", password: @pass)
    sign_in @player
    report(reason: "unclear")
    sign_in other
    report(reason: "unclear")
    assert @question.reload.retired?

    sign_in @admin
    first, second = @question.reports.order(:id).to_a
    post dismiss_admin_report_path(first)
    assert @question.reload.retired?, "another report is still waiting"
    post dismiss_admin_report_path(second)
    refute @question.reload.retired?
    assert_includes BibleQuizQuestion.trusted, @question
  end

  test "the type filter hides other reports" do
    other = User.create!(username: "qr_other", email: "qr_other@example.com", password: @pass)
    message = Conversation.find_or_create_between!(@player, other).messages.create!(sender: other, body: "Hello there")
    Report.create!(reporter: @player, reportable: message, reason: "Reported private message.")
    sign_in @player
    report(reason: "unclear")

    sign_in @admin
    get admin_reports_path
    assert_select "tbody tr", count: 2
    get admin_reports_path(type: "BibleQuizQuestion")
    assert_select "tbody tr", count: 1
    assert_select "td", text: /Quiz question ##{@question.id}/
  end

  # Two "resolved" reports once left their questions live and unchanged.
  test "a quiz report can't be resolved while the question is live and unchanged" do
    sign_in @player
    report(reason: "other", note: "Typo")
    r = Report.last

    sign_in @admin
    get admin_report_path(r)
    assert_select "a", text: "Edit question"
    assert_select "button", text: "Retire question"
    assert_select "button", text: "Resolve", count: 0

    post resolve_admin_report_path(r)
    assert_redirected_to admin_report_path(r)
    assert r.reload.pending?

    get admin_reports_path(type: "BibleQuizQuestion")
    assert_select "button", text: "Resolve", count: 0
  end

  test "editing the question fixes it, puts it back in the quiz and resolves its reports" do
    other = User.create!(username: "qr_other", email: "qr_other@example.com", password: @pass)
    sign_in @player
    report(reason: "wrong_answer")
    sign_in other
    report(reason: "unclear")
    assert @question.reload.retired?
    r = @question.reports.first

    sign_in @admin
    get edit_question_admin_report_path(r)
    assert_response :success
    assert_select "textarea[name='bible_quiz_question[prompt]']", text: @question.prompt

    patch update_question_admin_report_path(r), params: { bible_quiz_question: {
      prompt: "What did Jesus say just before he gave up the ghost?", correct_index: "0", reference: "John 19:30",
      explanation: "John 19:30 — It is finished.", choices: [ "It is finished", "Father, forgive them", "I thirst", "Into thy hands" ]
    } }
    assert_redirected_to admin_reports_path(type: "BibleQuizQuestion")
    @question.reload
    assert_equal 0, @question.correct_index
    assert_equal "What did Jesus say just before he gave up the ghost?", @question.prompt
    assert_not @question.retired?
    assert @question.reports.all?(&:resolved?)
  end

  test "an edit that still gives the answer away is refused" do
    q = BibleQuizQuestion.create!(kind: "reference", prompt: "'Jesus wept.' Where is this?", reference: "John 11:35",
                                  choices: [ "John 11:35", "Luke 19:41", "Mark 3:5", "John 3:16" ], correct_index: 0)
    sign_in @player
    report(reason: "unclear", question: q)
    r = Report.last

    sign_in @admin
    patch update_question_admin_report_path(r), params: { bible_quiz_question: {
      prompt: "John 11:35 says 'Jesus wept.' Where is this?", correct_index: "0", reference: "John 11:35",
      choices: q.choices
    } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /gives the answer away/
    assert r.reload.pending?
  end

  test "after retiring, a resolve goes through" do
    sign_in @player
    report(reason: "other", note: "Typo")
    r = Report.last
    @question.retire!

    sign_in @admin
    post resolve_admin_report_path(r)
    assert_redirected_to admin_reports_path
    assert r.reload.resolved?
  end
end
