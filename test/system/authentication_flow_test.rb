require "application_system_test_case"

# End-to-end auth happy path (plan §12): sign up → land in the app (onboarding is
# the minimal honest landing on Today) → sign out → sign back in.
class AuthenticationFlowTest < ApplicationSystemTestCase
  test "sign up, land in the app, sign out, and sign back in" do
    # --- Sign up -----------------------------------------------------------
    visit sign_up_path
    fill_in "Email", with: "newcomer@example.com"
    fill_in "Password", with: "supersecret"
    click_on "Create account"

    # Auto-logged-in and dropped into the app (Today).
    assert_text "Welcome to Saturday School"
    assert_selector "nav.tabbar"

    # --- Sign out (POST/DELETE button, not a link) -------------------------
    click_on "Sign out"
    assert_text "Signed out"
    assert_selector "h2", text: "Sign in"

    # --- Sign back in ------------------------------------------------------
    fill_in "Email", with: "newcomer@example.com"
    fill_in "Password", with: "supersecret"
    click_on "Sign in"

    assert_selector "nav.tabbar"
    # Protected page is reachable again.
    visit account_path
    assert_text "newcomer@example.com"
  end
end
