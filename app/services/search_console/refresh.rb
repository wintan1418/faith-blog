# frozen_string_literal: true

module SearchConsole
  # Fetches the reports the admin page shows and stores each one in
  # search_console_reports. A report that fails keeps its last good data and
  # records the error. Daily (SearchConsoleRefreshJob) and on "Refresh now".
  class Refresh
    PAGE_COUNT_LIMIT = 25_000 # searchanalytics.query's maximum rowLimit

    def self.call(client = SearchConsole.client, today: Date.current)
      new(client, today).call
    end

    def initialize(client, today)
      @client = client
      @today = today
    end

    def call
      errors = []
      PERIODS.each do |period, days|
        start_date, end_date = range(days)
        fetch("totals_#{period}", errors) { totals(start_date, end_date) }
        fetch("queries_#{period}", errors) { rows(start_date, end_date, "query") }
        fetch("pages_#{period}", errors) { rows(start_date, end_date, "page") }
      end
      fetch("pages_seen_3m", errors) do
        start_date, end_date = range(PERIODS["3m"])
        { "count" => @client.search_analytics(start_date: start_date, end_date: end_date, dimensions: [ "page" ],
                                              row_limit: PAGE_COUNT_LIMIT).size }
      end
      fetch("sitemaps", errors) { { "sitemaps" => @client.sitemaps } }
      SearchConsoleReport.store!("status", data: { "ok" => errors.empty? }, error: errors.presence&.uniq&.join("; "))
      errors
    end

    private

    # Search Console's numbers lag by a couple of days; ending yesterday keeps
    # both periods comparable.
    def range(days)
      end_date = @today - 1
      [ end_date - (days - 1), end_date ]
    end

    def totals(start_date, end_date)
      row = @client.search_analytics(start_date: start_date, end_date: end_date, dimensions: [], row_limit: 1).first || {}
      row.slice("clicks", "impressions", "ctr", "position").merge("start_date" => start_date.iso8601, "end_date" => end_date.iso8601)
    end

    def rows(start_date, end_date, dimension)
      list = @client.search_analytics(start_date: start_date, end_date: end_date, dimensions: [ dimension ], row_limit: TOP_ROWS)
      { "rows" => list.map { |r| { "key" => Array(r["keys"]).first, **r.slice("clicks", "impressions", "ctr", "position") } } }
    end

    def fetch(kind, errors)
      SearchConsoleReport.store!(kind, data: yield)
    rescue SearchConsole::Error => e
      errors << e.message
      SearchConsoleReport.store!(kind, error: e.message)
    end
  end
end
