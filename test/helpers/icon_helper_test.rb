# frozen_string_literal: true

require "test_helper"

class IconHelperTest < ActionView::TestCase
  test "icons draw with a real stroke-width attribute" do
    svg = render_icon("bell")
    assert_includes svg, 'stroke-width="2.25"'
    assert_not_includes svg, "stroke_width"
  end

  test "room emojis map to real icons, unknown names to a quiet dot" do
    assert_equal render_icon("sword"), render_icon("⚔️")
    assert_includes render_icon("no_such_icon"), ICONS["dot"]
  end

  test "room_icon_name maps the stored emoji" do
    assert_equal "pray", room_icon_name(Room.new(icon: "🙏"))
    assert_equal "users", room_icon_name(Room.new(icon: nil))
  end
end
