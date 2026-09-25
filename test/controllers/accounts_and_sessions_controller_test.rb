require "test_helper"

# S-03:AC-1 S-08:AC-3
class AccountsAndSessionsControllerTest < ActionDispatch::IntegrationTest
  test "a new account requires identity, a strong confirmed password, and ignores submitted privileges" do
    assert_difference("Account.count", 1) do
      post accounts_url, params: {
        account: {
          display_name: "New Player",
          email: "  New.Player@example.com  ",
          password: "a-long-test-password",
          password_confirmation: "a-long-test-password",
          role: "gm"
        }
      }
    end

    account = Account.find_by!(email: "new.player@example.com")
    assert_not account.has_attribute?("role")
    assert_not_equal "a-long-test-password", account.password_digest
    assert account.authenticate("a-long-test-password")
    assert_equal account.id, session[:account_id]
    assert_equal account.id, session[:authenticated_account_id]
    assert_redirected_to characters_url
  end

  test "account creation rejects missing credentials, a weak password, and a mismatched confirmation" do
    assert_no_difference("Account.count") do
      post accounts_url, params: { account: { display_name: "", email: "", password: "short", password_confirmation: "different" } }
    end

    assert_response :unprocessable_entity
    assert_select "[role='alert']", /Email can't be blank/
    assert_includes response.body, "Password is too short (minimum is 12 characters)"
    assert_includes Nokogiri::HTML(response.body).text, "Password confirmation doesn't match Password"
  end

  test "sign-in uses credentials rather than caller-supplied profile fields" do
    account = create_account(display_name: "Unchanged Name", email: "protected-#{SecureRandom.hex(4)}@example.com")
    original_email = account.email

    post session_url, params: {
      email: original_email,
      password: "wrong-password",
      display_name: "Impersonated Name",
      role: "gm"
    }

    assert_response :unprocessable_entity
    assert_select "[role='alert']", /Email or password is incorrect/
    assert_equal "Unchanged Name", account.reload.display_name
    assert_equal original_email, account.email
    assert_redirected_to new_session_url if response.redirect?
    get characters_url
    assert_redirected_to new_session_url

    post session_url, params: { email: original_email.upcase, password: TEST_PASSWORD }
    assert_redirected_to characters_url
    assert_equal account.id, session[:authenticated_account_id]
  end

  test "the former profile-only sign-in payload cannot authenticate an existing account" do
    account = create_account(display_name: "Protected Account", email: "legacy-#{SecureRandom.hex(4)}@example.com")

    post session_url, params: { account: { display_name: "Protected Account", email: account.email, role: "gm" } }

    assert_response :unprocessable_entity
    assert_equal "Protected Account", account.reload.display_name
    assert_nil session[:authenticated_account_id]
  end

  test "a pre-authentication session and a passwordless legacy account cannot grant access" do
    legacy_email = "legacy-profile-#{SecureRandom.hex(4)}@example.com"
    Account.insert!({
      display_name: "Legacy Profile",
      email: legacy_email,
      session_token: SecureRandom.hex(24),
      created_at: Time.current,
      updated_at: Time.current
    })
    legacy_account = Account.find_by!(email: legacy_email)

    get new_session_url
    session[:account_id] = legacy_account.id
    get characters_url

    assert_redirected_to new_session_url
    post session_url, params: { email: legacy_email, password: TEST_PASSWORD }
    assert_response :unprocessable_entity
    assert_nil session[:authenticated_account_id]
  end

  test "a duplicate email signup cannot overwrite the existing account" do
    account = create_account(display_name: "Existing Player", email: "already-registered-#{SecureRandom.hex(4)}@example.com")

    assert_no_difference("Account.count") do
      post accounts_url, params: {
        account: {
          display_name: "Attacker Name",
          email: account.email.upcase,
          password: "another-long-test-password",
          password_confirmation: "another-long-test-password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_equal "Existing Player", account.reload.display_name
    assert account.authenticate(TEST_PASSWORD)
    assert_not account.authenticate("another-long-test-password")
  end

  test "signing out clears authenticated access to private characters" do
    account = create_account(display_name: "Signed In Player", email: "sign-out-#{SecureRandom.hex(4)}@example.com")
    sign_in(account)
    character = Character.create!(account:, name: "Private Sign-out Hero")

    delete session_url

    assert_redirected_to new_session_url
    get character_url(character)
    assert_redirected_to new_session_url
  end
end
