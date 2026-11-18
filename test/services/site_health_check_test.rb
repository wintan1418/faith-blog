# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SiteHealthCheckTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    room = Room.create!(name: "Health Room", description: "x", room_type: :general, is_public: true)
    author = create_member("health_author", tour_completed_at: Time.current)
    Post.create!(user: author, room: room, title: "A breath", content: "Peace", status: :published, moderation_status: :approved)
  end

  test "signs in as the hidden monitor and finds every main page working" do
    alerts = []
    ErrorAlert.stub(:notify, ->(**kw) { alerts << kw }) do
      failures = SiteHealthCheck.call
      assert_empty failures, failures.map { |f| "#{f.path}: #{f.problem}" }.join(", ")
    end
    assert_empty alerts
    monitor = User.find_by(email: SiteHealthCheck::EMAIL)
    assert monitor.site_monitor?
    assert_not_includes User.active, monitor, "the monitor never shows in member lists"
    assert_equal 0, Announcement.where(user: monitor).count, "no 'new member' announcement"
  end

  test "a broken page raises an alert naming it" do
    alerts = []
    GamesController.class_eval do
      alias_method :__index_ok, :index
      define_method(:index) { raise "boom" }
    end
    ErrorAlert.stub(:notify, ->(**kw) { alerts << kw }) do
      failures = SiteHealthCheck.call
      assert_equal [ "/games" ], failures.map(&:path)
    end
    assert_match "Games", alerts.first[:title]
  ensure
    GamesController.class_eval { alias_method :index, :__index_ok } if GamesController.method_defined?(:__index_ok)
  end
end
