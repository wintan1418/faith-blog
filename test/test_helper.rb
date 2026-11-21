ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/klipy_stubs"

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

    # Rate-limit / bot counters live in an in-memory store under test; start
    # every test with a clean slate so suites don't trip each other's limits.
    setup { AuthThrottleStore.clear! }
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # The hidden fields a real sign-up form carries (SignupGuard): an empty
  # honeypot and a "form shown" stamp from long enough ago to be human.
  def human_signup_fields(shown_at: 10.seconds.ago)
    { SignupGuard::TOKEN_PARAM => SignupGuard.form_token(issued_at: shown_at), SignupGuard::HONEYPOT_PARAM => "" }
  end
end
