# frozen_string_literal: true

require "application_system_test_case"

# Trello #101: "Report this question" in the Bible Quiz, in the Android app.
class QuizReportQuestionTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; NativeShare; NativeDownloads; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  # Its own driver name: system test classes that share ":selenium" share one
  # browser, so another class's user agent and screen size would leak in.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ], options: { name: :android_quiz_report } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 900, pixelRatio: 2, touch: true })
  end

  setup do
    @player = create_member("quiz_reporter", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @question = BibleQuizQuestion.create!(
      kind: "what_does", prompt: "What did Jesus say on the cross just before he gave up the ghost (John 19:30)?",
      choices: [ "It is finished", "Father, forgive them", "I thirst", "Into thy hands" ],
      correct_index: 1, reference: "John 19:30", explanation: "KJV John 19:30: It is finished.",
      theme: "the_cross", difficulty: "easy"
    )
    login_as @player, scope: :user
  end

  teardown { Warden.test_reset! }

  test "a player reports a faulty question with a reason and a note" do
    visit games_quiz_path
    find(".fc-quiz-themepill", text: "The Cross").click
    click_on "Start the round"
    assert_selector ".fc-quiz-prompt", text: @question.prompt

    # Reportable before answering…
    assert_selector ".fc-quiz-report button", text: "Report this question"
    find(".fc-quiz-choice", text: "Father, forgive them").click
    assert_selector ".fc-quiz-explanation:not(.hidden)"

    # …and after.
    find(".fc-quiz-report button", text: "Report this question").click
    within ".fc-quiz-report-form" do
      assert_selector ".fc-quiz-report-reason", text: "Doesn't fit the theme"
      find(".fc-quiz-report-reason", text: "Wrong answer").click
      fill_in "Add a note (optional)", with: "His last words were \"It is finished\""
    end
    shot("101-report-question-form-light")

    click_on "Send report"
    assert_selector ".fc-quiz-report-done", text: "Thanks, question reported"
    report = @question.reports.last
    assert_equal 'Quiz question: Wrong answer. Note: His last words were "It is finished"', report.reason
    assert_equal @player, report.reporter

    # Still able to carry on with the round.
    assert_selector ".fc-quiz-next", text: "See result"
  end

  test "the form reads well in the dark theme, and Cancel puts the link back" do
    visit games_quiz_path
    page.execute_script("localStorage.setItem('fc-dark', '1')")
    visit games_quiz_path
    assert_selector "html.theme-dark"
    click_on "Start the round"
    find(".fc-quiz-choice", text: "It is finished").click
    find(".fc-quiz-report button", text: "Report this question").click
    # No theme picked, so no "doesn't fit the theme".
    assert_no_selector ".fc-quiz-report-reason", text: "Doesn't fit the theme"
    find(".fc-quiz-report-reason", text: "Unclear question").click
    shot("101-report-question-form-dark")
    click_on "Cancel"
    assert_selector ".fc-quiz-report button", text: "Report this question"
    assert_equal 0, Report.count
  ensure
    page.execute_script("localStorage.removeItem('fc-dark')") rescue nil
  end

  private

  def shot(name)
    dir = ENV["SHOT_DIR"]
    page.save_screenshot(File.join(dir, "#{name}.png")) if dir.present?
  end
end
