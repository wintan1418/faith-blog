ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Rails.application.reload_routes!

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Request counters for `rate_limit` (a memory store in tests) start fresh.
    setup { RateLimitStore.store.clear }

    # A throwaway member for a test. The password is random on every run.
    def create_member(username, **attrs)
      User.create!(username: username, email: "#{username}@example.com", password: SecureRandom.base58(24), **attrs)
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
