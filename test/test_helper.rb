ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    TEST_PASSWORD = "nimble-test-password".freeze

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_account(**attributes)
      Account.create!(
        { password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD }.merge(attributes)
      )
    end

    def sign_in(account, password: TEST_PASSWORD)
      if account.password_digest.blank? || !account.authenticate(password)
        account.update!(password:, password_confirmation: password)
      end

      post session_path, params: { email: account.email, password: }
      assert_redirected_to characters_path
    end
  end
end
