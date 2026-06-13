require "test_helper"

# Async turbo-stream appends (fetch + cable) can lag under load; give Capybara
# room to wait for them.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
end
