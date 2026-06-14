require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  test "the sign-up page is reachable without authentication" do
    get sign_up_path
    assert_response :success
    assert_select "h2", "Create your account"
  end

  test "valid signup creates a user, auto-logs-in, and lands in the app" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { Session.count }, 1 do
        post registration_path, params: { email_address: "new@example.com", password: "supersecret" }
      end
    end
    assert_redirected_to root_url
    assert User.find_by(email_address: "new@example.com").student?, "defaults to student role"
  end

  test "a too-short password re-renders with errors and creates nothing" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { email_address: "short@example.com", password: "nope" }
    end
    assert_response :unprocessable_entity
  end

  test "a duplicate email is enumeration-safe: no second account, no leak" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { Session.count } do
        post registration_path, params: { email_address: "owner@example.com", password: "supersecret" }
      end
    end
    # Generic, non-leaking response — never "email already taken".
    assert_redirected_to new_session_path
    assert_no_match(/already|taken/i, flash[:notice].to_s)
  end

  test "cannot mass-assign role on signup" do
    post registration_path, params: { email_address: "sneaky@example.com", password: "supersecret", role: "admin" }
    assert User.find_by(email_address: "sneaky@example.com").student?
  end
end
