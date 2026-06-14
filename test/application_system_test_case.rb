require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Mobile viewport: the review loop is the thumb-first primary surface (plan
  # §10, mockups), and the responsive app shell shows the bottom `nav.tabbar`
  # below the 860px breakpoint (above it, the desktop sidebar nav takes over and
  # the tabbar is hidden). These smoke tests assert on the tabbar, so they run at
  # a phone width where it is the visible navigation.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 414, 896 ]

  # Headless Chrome under load can take longer than the 2s default to settle a
  # Turbo-Stream swap; give Capybara's auto-waiting a more generous window so
  # genuine passes aren't lost to timing. (Only affects how long it waits.)
  Capybara.default_max_wait_time = 5

  # Sign in through the real UI (auth is secure-by-default since M5). Fixture
  # users share the password "password".
  def sign_in_through_ui(user, password: "password")
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: password
    click_on "Sign in"
    # Wait for the post-login page to settle (the tab nav only renders when
    # authenticated) before the test navigates on, so the session cookie is set.
    assert_selector "nav.tabbar"
  end
end
