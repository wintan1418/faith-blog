require "test_helper"

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
    if page.driver.respond_to?(:browser) && page.driver.browser.respond_to?(:execute_cdp)
      server = Capybara.current_session.server
      page.driver.browser.execute_cdp("Storage.clearDataForOrigin",
                                      origin: "http://#{server.host}:#{server.port}",
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
