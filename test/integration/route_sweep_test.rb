# frozen_string_literal: true

require "test_helper"
require_relative "../support/sweep_world"

# Every GET route in the app, opened by a signed-out visitor, a normal member
# and a super admin, as HTML and with a JSON Accept header (Nov 2026: "/"
# crashed for JSON clients). Nothing may answer 500. A new route with a path
# parameter must be taught to `SweepWorld#sweep_param_for`, so it can't slip past.
class RouteSweepTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SweepWorld

  # Engines and framework routes we don't own.
  SKIP_PREFIXES = %w[/rails/ /recede_ /resume_ /refresh_ /cable /up].freeze

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    build_sweep_world
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def get_routes
    Rails.application.routes.routes.filter_map do |route|
      next unless route.verb.to_s.include?("GET")
      next unless route.defaults[:controller] # redirects, mounted apps
      path = route.path.spec.to_s
      next if SKIP_PREFIXES.any? { |p| path.start_with?(p) }
      route
    end
  end

  def build_path(route)
    controller = route.defaults[:controller]
    path = route.path.spec.to_s.sub("(.:format)", "")
    missing = []
    path = path.gsub(/:(\w+)/) do
      value = sweep_param_for(controller, Regexp.last_match(1))
      missing << "#{controller}:#{Regexp.last_match(1)}" if value.nil?
      ERB::Util.url_encode(value.to_s)
    end
    [ path, missing ]
  end

  def sweep(label, headers: {})
    crashes = []
    unresolved = []
    get_routes.each do |route|
      path, missing = build_path(route)
      if missing.any?
        unresolved.concat(missing)
        next
      end
      begin
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        get path, headers: headers
        took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        warn "SLOW #{label} #{path} #{took.round(2)}s" if ENV["SWEEP_TIMING"] && took > 0.5
        crashes << "#{label} GET #{path} -> #{response.status}" if response.status >= 500
        # 406 to a browser means the page has no HTML view: a dead link.
        crashes << "#{label} GET #{path} -> 406 (no HTML view)" if response.status == 406 && headers.empty?
      rescue StandardError => e
        crashes << "#{label} GET #{path} raised #{e.class}: #{e.message.lines.first&.strip} (#{e.backtrace.find { |l| l.include?('/app/') }})"
      end
    end
    assert_empty unresolved.uniq, "Teach SweepWorld#sweep_param_for these route params"
    crashes
  end

  def check(label, user)
    sign_in user if user
    crashes = sweep("#{label} html")
    crashes += sweep("#{label} json", headers: { "Accept" => "application/json" })
    crashes += sweep("#{label} turbo", headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" })
    assert_empty crashes, crashes.join("\n")
  end

  test "no GET route crashes for a signed-out visitor" do
    check("guest", nil)
  end

  test "no GET route crashes for a signed-in member" do
    check("member", @member)
  end

  test "no GET route crashes for the other member (not the owner)" do
    check("other", @other)
  end

  test "no GET route crashes for a super admin" do
    check("admin", @admin)
  end
end
