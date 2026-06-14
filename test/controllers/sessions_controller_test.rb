require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out } # start unauthenticated; the global setup already signed us in

  test "the sign-in page is reachable without authentication" do
    get new_session_path
    assert_response :success
    assert_select "h2", "Sign in"
  end

  test "valid credentials sign the user in and set a session" do
    assert_difference -> { Session.count }, 1 do
      post session_path, params: { email_address: "owner@example.com", password: "password" }
    end
    assert_redirected_to root_url
  end

  test "a wrong password fails with a generic message and no session" do
    assert_no_difference -> { Session.count } do
      post session_path, params: { email_address: "owner@example.com", password: "wrong" }
    end
    assert_redirected_to new_session_path
    assert_equal "That email or password didn't match.", flash[:alert]
  end

  test "an unknown email fails identically (enumeration-safe)" do
    assert_no_difference -> { Session.count } do
      post session_path, params: { email_address: "nobody@example.com", password: "password" }
    end
    assert_redirected_to new_session_path
    assert_equal "That email or password didn't match.", flash[:alert]
  end

  test "signing out terminates the session" do
    sign_in_as(users(:owner))
    assert_difference -> { Session.count }, -1 do
      delete session_path
    end
    assert_redirected_to new_session_path
  end

  test "an unauthenticated request to a protected page redirects to sign in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "after signing in, the user is sent back to where they were headed (return_to)" do
    get progress_path # bounced to sign in; remembered
    assert_redirected_to new_session_path

    post session_path, params: { email_address: "owner@example.com", password: "password" }
    assert_redirected_to progress_url
  end
end
