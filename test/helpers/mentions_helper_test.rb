# frozen_string_literal: true

require "test_helper"

class MentionsHelperTest < ActionView::TestCase
  test "renders social text paragraphs line breaks mentions and links" do
    username = "formatfriend"
    User.find_or_create_by!(username: username) do |user|
      user.email = "formatfriend@example.test"
      user.password = "password123"
    end

    html = render_social_text("Hello there\nsame thought\n\nSecond paragraph for @#{username} https://example.com/path.")

    assert_includes html, "<p>Hello there<br>same thought</p>"
    assert_includes html, %(<p>Second paragraph for <a class="mention-link" href="/u/#{username}">@#{username}</a> )
    assert_includes html, %(href="https://example.com/path")
    assert_includes html, "https://example.com/path</a>.</p>"
  end

  test "escapes markup while preserving visible text" do
    html = render_social_text("<script>alert('x')</script>\nplain")

    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;<br>plain"
  end

  test "renders feed card text without block paragraphs" do
    html = render_social_card_text("First line\nsame paragraph\n\nNext paragraph", class_name: "fc-breath-copy")

    assert_includes html, %(class="fc-breath-copy")
    refute_includes html, "<p"
    assert_includes html, "First line<br>same paragraph<br><br>Next paragraph"
  end
end
