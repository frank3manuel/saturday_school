require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  # Signed in as users(:owner) via the global setup.

  test "shows the account page with the data-honesty section" do
    get account_path
    assert_response :success
    assert_select "h1", "Account"
    assert_select "#data-heading", text: "Your data"
  end

  test "changing email requires the current password and clears verification" do
    assert users(:owner).verified?
    patch account_path, params: {
      email_address: "moved@example.com", current_password: "password"
    }
    assert_redirected_to account_path
    owner = users(:owner).reload
    assert_equal "moved@example.com", owner.email_address
    assert_not owner.verified?, "a new email must re-verify"
  end

  test "a wrong current password blocks an email change" do
    patch account_path, params: {
      email_address: "nope@example.com", current_password: "wrong"
    }
    assert_response :unprocessable_entity
    assert_equal "owner@example.com", users(:owner).reload.email_address
  end

  test "changing the password keeps this session but destroys the others" do
    owner = users(:owner)
    # A second device's session that must be revoked on password change.
    other_device = owner.sessions.create!

    patch account_path, params: {
      commit_password: "1",
      current_password: "password",
      password: "brandnewpass",
      password_confirmation: "brandnewpass"
    }
    assert_redirected_to account_path
    assert owner.reload.authenticate("brandnewpass")
    assert_nil Session.find_by(id: other_device.id), "other sessions revoked"
    # The current session still works — we're still signed in.
    get account_path
    assert_response :success
  end

  test "exports the user's data as JSON" do
    owner = users(:owner)
    subject = owner.subjects.create!(name: "Exportable")
    subject.lessons.create!(title: "L1")

    get export_account_path
    assert_response :success
    assert_equal "application/json", response.media_type

    payload = JSON.parse(response.body)
    assert_equal "owner@example.com", payload.dig("account", "email_address")
    assert_includes payload["subjects"].map { |s| s["name"] }, "Exportable"
  end

  test "delete requires typing the exact email and then cascades" do
    owner = users(:owner)
    owner.subjects.create!(name: "Goes away")

    # Wrong confirmation → no deletion.
    assert_no_difference -> { User.count } do
      delete account_path, params: { confirm: "not-my-email" }
    end
    assert_response :unprocessable_entity

    # Correct confirmation → account + content cascade away.
    assert_difference -> { User.count }, -1 do
      delete account_path, params: { confirm: "owner@example.com" }
    end
    assert_redirected_to new_session_path
    assert_empty Subject.where(name: "Goes away")
  end
end
