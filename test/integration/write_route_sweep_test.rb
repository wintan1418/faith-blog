# frozen_string_literal: true

require "test_helper"
require_relative "../support/sweep_world"

# Every POST/PATCH/PUT/DELETE route, sent by a member, a super admin and a
# signed-out visitor with no params and with nonsense params (a stale form, a
# bot, a hand-edited request). A bad request may be refused (4xx) or bounced
# (3xx); it must never crash (500).
class WriteRouteSweepTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SweepWorld

  SKIP_PREFIXES = %w[/rails/ /recede_ /resume_ /refresh_ /cable].freeze

  JUNK = [
    {},
    { "id" => "nope", "post" => "x", "comment" => "x", "message" => "x", "q" => [ "a" ], "page" => "-3",
      "reaction_type" => "nonsense", "reaction_emoji" => "🦖🦖🦖", "likeable_type" => "Kernel",
      "reportable_type" => "User", "reportable_id" => "0", "conversation_ids" => [ "x" ], "direction" => "sideways",
      "score" => "lots", "details" => "x", "schedule_at" => "tomorrow-ish", "dark" => "maybe",
      "circle_breath" => "x", "circle_prayer" => "x", "circle" => "x", "reshare" => "x", "subscription" => "x", "keys" => "x",
      "profile" => "x", "user" => "x", "experience" => "x", "education" => "x", "certification" => "x", "portfolio_item" => "x",
      "brethren_card" => "x", "user_language" => "x", "invitation" => "x", "donation" => "x", "resource" => "x", "room" => "x",
      "announcement" => "x", "broadcast" => "x", "bible_verse" => "x", "golden_breath" => "x", "app_release" => "x", "import" => "x" },
    { "post" => { "content" => "", "status" => "bogus", "kind" => "bogus", "room_id" => "999999", "scheduled_for" => "not a date",
                  "quoted_post_id" => "999999", "images" => [ "not-a-file" ] },
      "comment" => { "content" => "" }, "message" => { "body" => "", "reply_to_id" => "999999" },
      "profile" => { "website" => "x" * 300 }, "user" => { "email" => "bad" }, "circle" => { "name" => "" } }
  ].freeze

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    build_sweep_world
    @connection_id = ConnectionRequest.first.id
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def write_routes
    Rails.application.routes.routes.filter_map do |route|
      verb = route.verb.to_s
      next unless verb.match?(/POST|PATCH|PUT|DELETE/)
      next unless route.defaults[:controller]
      next if SKIP_PREFIXES.any? { |p| route.path.spec.to_s.start_with?(p) }
      [ verb.split("|").first.downcase, route ]
    end
  end

  def param_for(controller, name)
    case [ controller, name ]
    in [ "comments", "post_id" ] | [ "bookmarks", "post_id" ] | [ "reshares", "post_id" ] then @post.to_param
    in [ "comments", "id" ] then @comment.id
    in [ "circle_breaths" | "circle_prayers", "circle_slug" ] then @circle.slug
    in [ "circle_breaths", "id" ] then @circle_breath.id
    in [ "circle_prayers", "id" ] then @circle_prayer.id
    in [ "likes", "likeable_type" ] then "Post"
    in [ "likes", "likeable_id" ] then @prayer.id
    in [ "endorsements" | "cards", "username" ] then @other.username
    in [ "users", "username" ] then @other.username
    in [ "messages", "id" ] then @file_message.id
    in [ "message_blocks", "user_id" ] then @other.id
    in [ "connection_requests", "id" ] then @connection_id
    in [ "invitations", "id" ] then 0
    in [ "whats_new", "id" ] then 0
    in [ "settings/languages", "id" ] then 0
    in [ "admin/office/conversations", "conversation_id" ] then @office_conversation.id
    in [ "giving", _ ] then "x"
    in [ "admin/bots", "id" ] then 0
    in [ "admin/announcements", "id" ] then 0
    in [ "admin/office/messages", "conversation_id" ] then @office_conversation.id
    else sweep_param_for(controller, name)
    end
  end

  def build_path(route)
    controller = route.defaults[:controller]
    missing = []
    path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:(\w+)/) do
      value = param_for(controller, Regexp.last_match(1))
      missing << "#{controller}:#{Regexp.last_match(1)}" if value.nil?
      ERB::Util.url_encode(value.to_s)
    end
    [ path, missing ]
  end

  def sweep(label, user)
    crashes = []
    unresolved = []
    write_routes.each do |verb, route|
      path, missing = build_path(route)
      next unresolved.concat(missing) if missing.any?

      JUNK.each_with_index do |params, i|
        # A fresh copy each time: Warden keeps the very object it was given.
        sign_in User.find_by(id: user.id) || user if user
        begin
          send(verb, path, params: params)
          # 502/503 are deliberate "the AI is unavailable, try again" answers.
          crashes << "#{label} #{verb.upcase} #{path} (junk #{i}) -> #{response.status}" if response.status >= 500 && ![ 502, 503 ].include?(response.status)
        rescue StandardError => e
          crashes << "#{label} #{verb.upcase} #{path} (junk #{i}) raised #{e.class}: #{e.message.lines.first&.strip&.first(160)} " \
                     "(#{e.backtrace.find { |l| l.include?('/app/') }})"
        end
      end
    end
    assert_empty unresolved.uniq, "Teach WriteRouteSweepTest#param_for (or SweepWorld#sweep_param_for) these route params"
    crashes
  end

  test "no write route crashes on missing or nonsense params for a member" do
    crashes = sweep("member", @member)
    assert_empty crashes, crashes.join("\n")
  end

  test "no write route crashes on missing or nonsense params for a super admin" do
    crashes = sweep("admin", @admin)
    assert_empty crashes, crashes.join("\n")
  end

  test "no write route crashes for a signed-out visitor" do
    crashes = sweep("guest", nil)
    assert_empty crashes, crashes.join("\n")
  end
end
