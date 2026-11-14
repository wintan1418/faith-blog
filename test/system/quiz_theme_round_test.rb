# frozen_string_literal: true

require "application_system_test_case"

# Trello #102: picking "The Cross" in the Android app gives only questions on
# the cross, and says so when there aren't enough for the round yet.
class QuizThemeRoundTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.9; Hotwire Native Android; Turbo Native Android; NativeShare; NativeDownloads; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  # Its own driver name: system test classes that share ":selenium" share one
  # browser, so another class's user agent and screen size would leak in.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ], options: { name: :android_quiz_theme } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
    options.add_emulation(device_metrics: { width: 412, height: 900, pixelRatio: 2, touch: true })
  end

  setup do
    @player = create_member("quiz_theme", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    [ "What did Christ make through the blood of his cross? (Colossians 1:20)",
      "Complete: \"God forbid that I should glory, save in the ___ of our Lord Jesus Christ\" (Galatians 6:14)",
      "Who bore our sins in his own body on the tree? (1 Peter 2:24)" ].each_with_index do |prompt, i|
      BibleQuizQuestion.create!(kind: "what_does", prompt: prompt, choices: [ "Peace", "Cross", "Christ", "Law" ].rotate(i),
                                correct_index: 0, reference: "Colossians 1:20", explanation: "KJV", theme: "the_cross", difficulty: "easy")
    end
    12.times do |i|
      BibleQuizQuestion.create!(kind: "which_book", prompt: "Unrelated question #{i} about Jericho?",
                                choices: %w[Joshua Judges Ruth Esther], correct_index: 0, theme: "bible_history", difficulty: "easy")
    end
    login_as @player, scope: :user
  end

  teardown { Warden.test_reset! }

  test "The Cross gives only questions on the cross" do
    visit games_quiz_path
    find(".fc-quiz-themepill", text: "The Cross").click
    click_on "Start the round"

    assert_selector ".fc-quiz-hud-progress", text: %r{Question 1 / 3}i
    assert_selector ".fc-quiz-notice", text: "Only 3 questions on The Cross so far"
    sleep 0.8 # let the card finish fading in for the screenshot
    shot("102-theme-round-the-cross")

    3.times do |i|
      assert_selector ".fc-quiz-tag.is-theme", text: /the cross/i
      assert_no_text "Unrelated question"
      first(".fc-quiz-choice").click
      find(".fc-quiz-next").click
      assert_no_selector ".fc-quiz-hud-progress", text: %r{Question #{i + 1} / 3}i if i < 2
    end
    assert_selector ".fc-quiz-result"
  end

  private

  def shot(name)
    dir = ENV["SHOT_DIR"]
    page.save_screenshot(File.join(dir, "#{name}.png")) if dir.present?
  end
end
