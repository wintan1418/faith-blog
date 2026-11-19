require "test_helper"
require "capybara/selenium/driver"

# Capybara (3.40) clears storage between tests with
# Storage.clearDataForOrigin(origin: "*"), which Chrome 158 rejects
# ("* is not a valid URL"), failing every system test. Clear the test
# server's origin instead, and cookies through the Network domain.
module ChromeResetForCurrentChrome
  mattr_accessor :origin

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies") if params[:storageTypes].to_s.include?("cookies")
    super(cmd, params.merge(origin: ChromeResetForCurrentChrome.origin)) if ChromeResetForCurrentChrome.origin
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeResetForCurrentChrome)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Every driven_by needs its own driver name: Capybara keeps one browser per
  # name, so classes sharing :selenium got whichever browser (user agent,
  # screen size) was set up first.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: { name: :desktop_chrome }

  # A service worker registered by an earlier test stays in the browser and,
  # on the next visit, fetches /service-worker.js, /feed and /offline itself.
  # Those requests can take Warden's one-shot login_as, so the page under test
  # ends up signed out. Start each test without one.
  setup do
    server = Capybara.current_session.server
    ChromeResetForCurrentChrome.origin = "http://#{server.host}:#{server.port}"
    if page.driver.respond_to?(:browser) && page.driver.browser.respond_to?(:execute_cdp)
      page.driver.browser.execute_cdp("Storage.clearDataForOrigin",
                                      origin: ChromeResetForCurrentChrome.origin,
                                      storageTypes: "service_workers,cache_storage")
    end
  end

  # The Brethreign splash covers the page for at least 400ms after each full
  # load; a press made under it lands on the splash, not the page. Wait until
  # it lets taps through (it gets .is-leaving and pointer-events: none).
  def visit(...)
    super
    assert_no_selector "#fc-splash:not(.is-leaving)", visible: :all, wait: 5
  end
end
