# frozen_string_literal: true

require "test_helper"

class Ai::Office::RunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Reply = Ai::Office::Reply
  Stub = Ai::Office::Providers::Stub

  setup do
    ENV["OFFICE_STUB"] = "1"
    Stub.reset!
    @admin = create_member("office_admin_#{SecureRandom.hex(3)}", role: :admin)
    @conversation = @admin.office_conversations.create!
  end

  teardown do
    ENV.delete("OFFICE_STUB")
    ENV.delete("OFFICE_POST_AS")
    Stub.reset!
  end

  def say(text)
    @conversation.messages.create!(role: :user, content: text)
  end

  def tool_call(name, input, id: "call_#{SecureRandom.hex(3)}")
    Reply.new(text: "", tool_calls: [ { "id" => id, "name" => name, "input" => input } ], model: "stub")
  end

  def run!
    Ai::Office::Runner.new(@conversation, provider: Stub.new).run
    @conversation.reload
  end

  test "a plain reply is saved as an assistant message and the thread stops thinking" do
    @conversation.update!(thinking: true)
    say "Hello"
    Stub.script(Reply.new(text: "Hello, Wintan.", model: "stub"))

    run!

    assert_equal "Hello, Wintan.", @conversation.messages.assistant.last.content
    assert_not @conversation.thinking?
    assert @conversation.last_message_at.present?
  end

  test "draft_breath makes a card and posts nothing" do
    say "Draft a breath"
    Stub.script(tool_call("draft_breath", { "body" => "Rest in Him today.", "prayer_request" => true }),
                Reply.new(text: "Here it is.", model: "stub"))

    assert_no_difference -> { Post.count } do
      run!
    end

    tool = @conversation.messages.tool.last
    assert_equal "draft_breath", tool.tool_name
    assert_equal "breath", tool.card_kind
    assert_equal "draft", tool.card_data["status"]
    assert_equal "Rest in Him today.", tool.card_data["body"]
    assert tool.card_data["prayer"]
    assert_equal "Here it is.", @conversation.messages.last.content
  end

  test "draft_breath with publish: true posts as the admin straight away" do
    say "Post this without asking me"
    Stub.script(tool_call("draft_breath", { "body" => "Good morning, brethren.", "publish" => true }),
                Reply.new(text: "Posted.", model: "stub"))

    assert_difference -> { Post.count }, 1 do
      run!
    end

    post = Post.order(:id).last
    assert_equal @admin, post.user
    assert post.published?
    assert post.moderation_approved?
    assert_equal "posted", @conversation.messages.tool.last.card_data["status"]
  end

  test "breaths go out from OFFICE_POST_AS when it names a staff account" do
    official = create_member("brethreign_#{SecureRandom.hex(2)}", role: :super_admin)
    ENV["OFFICE_POST_AS"] = official.username
    assert_equal official, Ai::Office::BreathPublisher.author_for(@admin)

    member = create_member("member_#{SecureRandom.hex(2)}")
    ENV["OFFICE_POST_AS"] = member.username
    assert_equal @admin, Ai::Office::BreathPublisher.author_for(@admin), "a non-staff account is never used"
  end

  test "draft_breath with a future schedule_at and publish schedules the post" do
    say "Schedule it for tomorrow"
    at = 1.day.from_now.in_time_zone("Africa/Lagos").strftime("%Y-%m-%dT%H:%M")
    Stub.script(tool_call("draft_breath", { "body" => "See you tomorrow.", "publish" => true, "schedule_at" => at }),
                Reply.new(text: "Scheduled.", model: "stub"))

    run!

    post = Post.order(:id).last
    assert post.scheduled?
    assert_nil post.published_at
    assert post.scheduled_for > Time.current
  end

  test "draft_email saves a draft broadcast and never sends it" do
    say "Draft a thank-you email"
    Stub.script(tool_call("draft_email", { "subject" => "Thank you for breathing with us", "preheader" => "A short note",
                                           "body_html" => "<p>Dear friend, thank you for being part of Brethreign from the start.</p>" }),
                Reply.new(text: "Saved as a draft.", model: "stub"))

    assert_difference -> { Broadcast.count }, 1 do
      assert_no_enqueued_jobs(only: BroadcastFanoutJob) { run! }
    end

    broadcast = Broadcast.order(:id).last
    assert broadcast.draft?
    assert_nil broadcast.sent_at
    assert_equal @admin, broadcast.sender
    card = @conversation.messages.tool.last.card_data
    assert_equal broadcast.id, card["broadcast_id"]
    assert_equal "draft_saved_not_sent", @conversation.messages.tool.last.payload.dig("result", "status")
  end

  test "generate_flyer stores an image on the card" do
    say "Make a flyer"
    Stub.script(tool_call("generate_flyer", { "brief" => "A sunrise over a garden", "size" => "story" }),
                Reply.new(text: "Here's the flyer.", model: "stub"))

    run!

    tool = @conversation.messages.tool.last
    assert tool.image.attached?
    assert_equal "image/png", tool.image.blob.content_type
    assert_equal "story", tool.card_data["size"]
  end

  test "site_stats returns the dashboard numbers to the model" do
    say "How many people joined this week?"
    Stub.script(tool_call("site_stats", { "days" => 7 }), Reply.new(text: "Numbers are in.", model: "stub"))

    run!

    result = @conversation.messages.tool.last.payload["result"]
    assert_equal User.count, result["members_total"]
    assert(result["headline"].any? { |k| k["label"] == "New members" })
  end

  test "an unknown tool is reported back as an error, not raised" do
    say "Do something odd"
    Stub.script(tool_call("delete_everything", {}), Reply.new(text: "I can't do that.", model: "stub"))

    run!

    assert_match "Unknown tool", @conversation.messages.tool.last.payload.dig("result", "error")
  end

  test "the tool loop stops after MAX_TOOL_ROUNDS" do
    say "Loop forever"
    Stub.script(Array.new(Ai::Office::Runner::MAX_TOOL_ROUNDS + 2) { tool_call("site_stats", {}) })

    run!

    assert_equal Ai::Office::Runner::MAX_TOOL_ROUNDS, @conversation.messages.tool.count
    assert_match "paused", @conversation.messages.last.content
  end

  test "a provider failure leaves a friendly retry message" do
    say "Hello"
    failing = Stub.new
    def failing.chat(**) = raise(Ai::Office::Client::ApiError, "boom")

    Ai::Office::Runner.new(@conversation, provider: failing).run

    last = @conversation.messages.last
    assert last.failed?
    assert_equal Ai::Office::Runner::FRIENDLY_ERROR, last.content
    assert_not @conversation.reload.thinking?
  end

  test "history starts at the founder's words, skips failures and answers every tool call" do
    @conversation.messages.create!(role: :tool, content: "{}", payload: { "tool_call_id" => "orphan", "name" => "site_stats", "result" => {} })
    say "First"
    @conversation.messages.create!(role: :assistant, content: "Oops", payload: { "error" => true })
    @conversation.messages.create!(role: :assistant, content: "", payload: { "tool_calls" => [ { "id" => "c1", "name" => "site_stats", "input" => {} } ] })
    @conversation.messages.create!(role: :user, content: "Notes", payload: { "imported" => true })

    history = Ai::Office::Runner.new(@conversation, provider: Stub.new).history

    assert_equal :user, history.first[:role]
    assert_equal "First", history.first[:text]
    assert_not(history.any? { |m| m[:text] == "Oops" })
    filler = history.find { |m| m[:role] == :tool }
    assert_equal "c1", filler[:tool_call_id]
    assert_match "Notes imported", history.last[:text]
  end

  test "history keeps only the most recent messages" do
    (Ai::Office::Runner::HISTORY_LIMIT + 10).times { |i| say "Message #{i}" }

    history = Ai::Office::Runner.new(@conversation, provider: Stub.new).history

    assert_equal Ai::Office::Runner::HISTORY_LIMIT, history.size
    assert_equal "Message #{Ai::Office::Runner::HISTORY_LIMIT + 9}", history.last[:text]
  end

  test "the briefing is part of the system prompt" do
    OfficeBriefing.current.update!(body: "Sign off as Wintan, Chief Steward.")
    prompt = Ai::Office::SystemPrompt.build(briefing: OfficeBriefing.current.body, user: @admin)
    assert_includes prompt, "Sign off as Wintan, Chief Steward."
    assert_includes prompt, "British spelling"
  end
end
