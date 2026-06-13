require "test_helper"

# Async turbo-stream appends (fetch + cable) can lag under load; give Capybara
# room to wait for them.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  # Logs a user in and waits until the redirect away from the login form has
  # landed (avoids racing a not-yet-submitted Turbo form under load).
  def sign_in(user, password: "password")
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    # Retry the submit: under load the first click can land before Turbo is
    # ready and get swallowed, leaving us on the login form.
    3.times do
      click_on "Sign in"
      return if has_no_selector?("input[name=email_address]", wait: 2)
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
    end
    assert_no_selector "input[name=email_address]"
  end
end
