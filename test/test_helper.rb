ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # PostgreSQL connections segfault after fork on macOS with the current pg gem.
    # Keep local macOS runs serial while retaining parallel workers on Linux CI.
    parallelize(workers: RUBY_PLATFORM.match?(/darwin/) ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
