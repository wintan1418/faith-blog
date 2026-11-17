require "test_helper"

# The site shows icons where push/email text keeps its emoji.
class EvergreenIconsTest < ActiveSupport::TestCase
  include IconHelper

  test "every notification type has a web icon that exists" do
    Notification.notification_types.each_key do |type|
      name = Notification.new(notification_type: type).web_icon
      assert ICONS.key?(name), "#{type} → #{name} is not in IconHelper::ICONS"
    end
  end

  test "web_message drops the emoji; message (push and email) keeps it" do
    note = Notification.new(notification_type: :prayer_answered)
    assert_equal "A prayer you joined was just marked answered 🌟", note.message
    assert_equal "A prayer you joined was just marked answered", note.web_message
  end

  test "badges and portfolio categories have icons that exist" do
    UserBadge::CATALOG.each_value { |b| assert ICONS.key?(b[:icon]), b[:name] }
    PortfolioItem::CATEGORIES.each_key do |cat|
      assert ICONS.key?(PortfolioItem.new(category: cat).icon), cat
    end
    Bots::Catalog::ALL.each { |b| assert ICONS.key?(b.icon), b.key }
  end

  test "stored emoji map to icons" do
    assert_equal "cake", emoji_icon_name("🎂")
    assert_equal "sparkles", emoji_icon_name("🦄")
  end
end
