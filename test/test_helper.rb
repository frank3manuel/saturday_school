ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Sign-in helpers for integration/system tests. Authentication is
# secure-by-default (plan §7), so every M1–M4 page now requires a signed-in
# user; integration tests sign in `users(:owner)` by default in setup so they
# stay green, and the cross-user tests sign in explicitly as needed.
module SignInHelper
  # Integration tests: authenticate by exercising the real sign-in endpoint, so
  # the signed session cookie is set exactly as in production.
  def sign_in_as(user, password: "password")
    post session_url, params: { email_address: user.email_address, password: password }
    user
  end

  def sign_out
    delete session_url
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper

  # Default: every integration test runs as the owner unless it signs in as
  # someone else. Tests that need an unauthenticated context call `sign_out`.
  setup { sign_in_as(users(:owner)) }
end
