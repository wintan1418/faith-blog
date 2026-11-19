# frozen_string_literal: true

require "application_system_test_case"

# In the iPhone app the "Continue with Apple" button showed as a blank white
# box: the light theme painted every sign-in button white over Apple's black
# while the text turned white. Apple's button must be black with white text.
class AppleSignInButtonTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :ios_apple_sign_in } do |options|
    options.add_argument("--user-agent=Brethreign/1.0.9; NativeShare; NativeDownloads; NativeAppleSignIn; Hotwire Native iOS; Turbo Native iOS")
  end

  test "Continue with Apple is black with white text" do
    visit new_user_session_path
    page.execute_script("document.documentElement.classList.add('theme-light')")
    button = find("a.apple-auth-button", text: "Continue with Apple")
    colors = page.evaluate_script(<<~JS, button)
      (el => { const s = getComputedStyle(el); return [s.backgroundColor, s.color] })(arguments[0])
    JS
    assert_equal [ "rgb(0, 0, 0)", "rgb(255, 255, 255)" ], colors
  end
end
