require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_out }

  test "the forgot-password page is reachable without authentication" do
    get new_password_path
    assert_response :success
    assert_select "h2", "Reset your password"
  end

  test "requesting a reset for a real account sends exactly one email" do
    assert_emails 1 do
      perform_enqueued_jobs do
        post passwords_path, params: { email_address: "owner@example.com" }
      end
    end
    assert_redirected_to new_session_path
  end

  test "requesting a reset for an unknown email is enumeration-safe: same message, no email" do
    assert_no_emails do
      perform_enqueued_jobs do
        post passwords_path, params: { email_address: "nobody@example.com" }
      end
    end
    assert_redirected_to new_session_path
    # Identical confirmation regardless of whether the account exists.
    assert_match(/if an account exists/i, flash[:notice])
  end

  test "the unknown-email and known-email confirmations are identical" do
    post passwords_path, params: { email_address: "owner@example.com" }
    known = flash[:notice]
    post passwords_path, params: { email_address: "nobody@example.com" }
    unknown = flash[:notice]
    assert_equal known, unknown
  end

  test "a valid token lets the user set a new password (full flow)" do
    user = users(:owner)
    token = user.generate_token_for(:password_reset)

    patch password_path(token), params: { password: "brandnewpass", password_confirmation: "brandnewpass" }
    assert_redirected_to new_session_path

    # The new password works; the old one no longer does.
    assert User.authenticate_by(email_address: user.email_address, password: "brandnewpass")
    assert_nil User.authenticate_by(email_address: user.email_address, password: "password")
  end

  test "an expired token is a friendly dead-end-free redirect, not a crash" do
    user = users(:owner)
    token = user.generate_token_for(:password_reset)

    travel 16.minutes do
      get edit_password_path(token)
      assert_redirected_to new_password_path
      assert_match(/invalid or has expired/i, flash[:alert])
    end
  end

  test "changing the password invalidates the reset token (token reuse blocked)" do
    user = users(:owner)
    token = user.generate_token_for(:password_reset)
    user.update!(password: "somethingelse")

    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "a too-short new password re-renders the form" do
    token = users(:owner).generate_token_for(:password_reset)
    patch password_path(token), params: { password: "short", password_confirmation: "short" }
    assert_response :unprocessable_entity
  end
end
