# frozen_string_literal: true

require "test_helper"

class ErrorAlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @store }

  test "one alert per problem every 15 minutes, counting repeats" do
    assert_enqueued_jobs 1, only: ErrorAlertJob do
      3.times { ErrorAlert.notify(key: "X|app/a.rb:1", title: "/inbox is crashing", detail: "boom") }
    end
    travel 16.minutes do
      assert_enqueued_with(job: ErrorAlertJob, args: [ "/inbox is crashing", "boom", 3 ]) do
        ErrorAlert.notify(key: "X|app/a.rb:1", title: "/inbox is crashing", detail: "boom")
      end
    end
  end

  test "the job emails the admins" do
    admin = create_member("alert_admin")
    admin.update_columns(role: User.roles[:admin])
    assert_emails 1 do
      ErrorAlertJob.perform_now("/inbox is crashing", "boom", 1)
    end
    assert_equal [ admin.email ], ActionMailer::Base.deliveries.last.to
  end
end
