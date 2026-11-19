# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class FeatureFailureTest < ActiveSupport::TestCase
  setup do
    @store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @store }

  test "alerts the admins once a feature fails three times in an hour" do
    alerts = []
    ErrorAlert.stub(:notify, ->(**kw) { alerts << kw }) do
      2.times { FeatureFailure.record(:linkedin_import, "Reading the PDF didn't work") }
      assert_empty alerts
      FeatureFailure.record(:linkedin_import, "Reading the PDF didn't work")
    end
    assert_equal 1, alerts.size
    assert_match "Linkedin import keeps failing", alerts.first[:title]
  end

  test "a member's wrong file never counts" do
    assert LinkedinImport::MemberError.new("x").member_fault?
    assert_not LinkedinImport::Error.new("x").member_fault?
  end
end
