# frozen_string_literal: true

require "test_helper"

class ChatTextHelperTest < ActionView::TestCase
  include ChatTextHelper

  test "a Brethreign link becomes a link that stays in the app" do
    html = chat_text("Take it here: https://brethreign.com/feedback/1")
    assert_includes html, %(<a href="https://brethreign.com/feedback/1" class="msg-link" data-turbo-frame="_top">https://brethreign.com/feedback/1</a>)
  end

  test "another site opens in a new tab, and the full stop after it isn't part of it" do
    html = chat_text("See https://example.org/a?b=1&c=2.")
    assert_includes html, %(href="https://example.org/a?b=1&amp;c=2")
    assert_includes html, %(target="_blank" rel="noopener noreferrer nofollow ugc")
    assert_includes html, "</a>.</p>"
  end

  test "the text around links is escaped, and quotes end a link" do
    html = chat_text(%(<script>x</script> "https://evil.test/x" onclick="y"))
    assert_not_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
    assert_includes html, %(href="https://evil.test/x")
    assert_not_includes html, %(href="https://evil.test/x&quot;)
  end

  test "line breaks and paragraphs are kept; text without links is unchanged" do
    html = chat_text("Hi Tolu\n\nThank you\nWintan")
    assert_equal "<p>Hi Tolu</p>\n\n<p>Thank you\n<br />Wintan</p>", html
  end

  test "javascript: and other schemes are never linked" do
    assert_not_includes chat_text("javascript:alert(1) ftp://x.test"), "<a "
  end
end
