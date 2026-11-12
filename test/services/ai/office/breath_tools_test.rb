# frozen_string_literal: true

require "test_helper"

# Breaths and flyers together: ids in tool results, draft_breath with
# flyer_id, update_breath and generate_flyer with for_breath_id.
class Ai::Office::BreathToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Reply = Ai::Office::Reply
  Stub = Ai::Office::Providers::Stub

  setup do
    ENV["OFFICE_STUB"] = "1"
    Stub.reset!
    @admin = create_member("office_admin_#{SecureRandom.hex(3)}", role: :admin)
    @conversation = @admin.office_conversations.create!
    @conversation.messages.create!(role: :user, content: "Let's make a breath and a flyer")
  end

  teardown do
    ENV.delete("OFFICE_STUB")
    Stub.reset!
  end

  def tool_call(name, input)
    Reply.new(text: "", tool_calls: [ { "id" => "call_#{SecureRandom.hex(3)}", "name" => name, "input" => input } ], model: "stub")
  end

  # Runs one tool through the runner, as the model would, and returns its message.
  def run_tool(name, input)
    Stub.script(tool_call(name, input), Reply.new(text: "Done.", model: "stub"))
    Ai::Office::Runner.new(@conversation, provider: Stub.new).run
    @conversation.messages.tool.reorder(:id).last
  end

  def flyer! = run_tool("generate_flyer", { "brief" => "Sunrise over a garden" })

  def posted_breath!(body: "The hidden years matter.")
    breath = run_tool("draft_breath", { "body" => body, "title" => "The Hidden Years" })
    result = Ai::Office::BreathPublisher.new(card: breath.card_data, admin: @admin).call
    breath.update_card!(Ai::Office::BreathPublisher.card_attrs_for(result.post))
    [ breath.reload, result.post ]
  end

  test "generate_flyer and draft_breath tell the model their card ids" do
    flyer = flyer!
    assert_equal flyer.id, flyer.payload.dig("result", "flyer_id")
    assert_equal flyer.id, JSON.parse(flyer.content)["flyer_id"]

    breath = run_tool("draft_breath", { "body" => "Rest today." })
    assert_equal breath.id, breath.payload.dig("result", "breath_id")
  end

  test "draft_breath with flyer_id shows the flyer and posts with it" do
    flyer = flyer!
    breath = run_tool("draft_breath", { "body" => "Morning light.", "flyer_id" => flyer.id })

    assert_equal flyer.id, breath.card_data["image_message_id"]
    assert_equal flyer.id, breath.payload.dig("result", "flyer_id")

    post = Ai::Office::BreathPublisher.new(card: breath.card_data, admin: @admin).call.post
    assert_equal flyer.image.blob, post.images.first.blob
  end

  test "draft_breath refuses a flyer_id from another conversation" do
    other = @admin.office_conversations.create!
    stranger = other.messages.create!(role: :tool, content: "{}", payload: { "card" => { "kind" => "flyer" } })
    stranger.image.attach(io: StringIO.new("x"), filename: "x.png", content_type: "image/png")

    breath = run_tool("draft_breath", { "body" => "Hi", "flyer_id" => stranger.id })
    assert_match "isn't an image in this conversation", breath.payload.dig("result", "error")
  end

  test "update_breath changes a draft card in place and attaches a flyer" do
    breath = run_tool("draft_breath", { "body" => "First words." })
    flyer = flyer!

    assert_no_difference -> { @conversation.messages.where("payload -> 'card' ->> 'kind' = 'breath'").count } do
      tool = run_tool("update_breath", { "breath_id" => breath.id, "body" => "Better words.", "flyer_id" => flyer.id })
      assert_equal "card_updated", tool.payload.dig("result", "status")
    end

    card = breath.reload.card_data
    assert_equal "Better words.", card["body"]
    assert_equal flyer.id, card["image_message_id"]
    assert_equal "draft", card["status"]

    run_tool("update_breath", { "breath_id" => breath.id, "remove_flyer" => true })
    assert_nil breath.reload.card_data["image_message_id"]
  end

  test "update_breath on a posted breath updates the live post: image added, other images and moderation kept" do
    breath, post = posted_breath!
    other_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(Ai::Office::ImageGenerator.new.generate(prompt: "x", size: "square").bytes),
                                                        filename: "mine.png", content_type: "image/png")
    post.images.attach(other_blob)
    flyer = flyer!

    tool = run_tool("update_breath", { "breath_id" => breath.id, "flyer_id" => flyer.id, "body" => "The hidden years matter.\n\nGod sees them." })
    assert_equal "live_post_updated", tool.payload.dig("result", "status")

    post.reload
    assert_equal [ other_blob.id, flyer.image.blob.id ].sort, post.images.map(&:blob_id).sort
    assert_match "God sees them.", post.content.to_plain_text
    assert post.moderation_approved?
    card = breath.reload.card_data
    assert_equal "posted", card["status"]
    assert card["updated_at"].present?
    assert_equal flyer.image.blob.id, card["post_image_blob_id"]

    # Replacing the flyer swaps only the Office's image; the flyer's file survives.
    second = flyer!
    run_tool("update_breath", { "breath_id" => breath.id, "flyer_id" => second.id })
    perform_enqueued_jobs
    assert_equal [ other_blob.id, second.image.blob.id ].sort, post.reload.images.map(&:blob_id).sort
    assert flyer.reload.image.attached?
    assert ActiveStorage::Blob.exists?(flyer.image.blob.id)
  end

  test "generate_flyer with for_breath_id attaches the new flyer to that breath" do
    breath = run_tool("draft_breath", { "body" => "Words." })
    flyer = run_tool("generate_flyer", { "brief" => "Garden", "for_breath_id" => breath.id })

    assert_equal flyer.id, breath.reload.card_data["image_message_id"]
    assert_equal breath.id, flyer.payload.dig("result", "attached_to_breath_id")
  end

  test "generate_flyer for a posted breath puts the image on the live post" do
    breath, post = posted_breath!
    flyer = run_tool("generate_flyer", { "brief" => "Garden", "for_breath_id" => breath.id })

    assert_equal [ flyer.image.blob.id ], post.reload.images.map(&:blob_id)
  end

  test "generate_flyer with an unknown for_breath_id makes no image" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      tool = run_tool("generate_flyer", { "brief" => "Garden", "for_breath_id" => 0 })
      assert_match "isn't a breath card", tool.payload.dig("result", "error")
    end
  end

  test "history gives cards made before ids existed their ids and current state" do
    old_flyer = @conversation.messages.create!(role: :tool, content: "{}", payload: {
      "tool_call_id" => "f_old", "name" => "generate_flyer", "result" => { "status" => "image_ready" }, "card" => { "kind" => "flyer", "brief" => "x" }
    })
    old_breath = @conversation.messages.create!(role: :tool, content: "{}", payload: {
      "tool_call_id" => "b_old", "name" => "draft_breath", "result" => { "status" => "card_shown" },
      "card" => { "kind" => "breath", "status" => "posted", "post_id" => 304, "title" => "The Hidden Years", "body" => "..." }
    })
    ui_card = @conversation.messages.create!(role: :card, content: "The founder started a breath using the flyer.",
                                             payload: { "card" => { "kind" => "breath", "status" => "draft", "image_message_id" => old_flyer.id } })
    @conversation.messages.create!(role: :assistant, content: "", payload: { "tool_calls" => [
      { "id" => "f_old", "name" => "generate_flyer", "input" => {} }, { "id" => "b_old", "name" => "draft_breath", "input" => {} }
    ] })

    history = Ai::Office::Runner.new(@conversation, provider: Stub.new).history
    entries = history.select { |m| m[:role] == :tool }.index_by { |m| m[:tool_call_id] }
    assert_equal old_flyer.id, entries["f_old"][:result]["flyer_id"]
    assert_equal old_breath.id, entries["b_old"][:result]["breath_id"]
    assert_equal "posted", entries["b_old"][:result].dig("card_now", "status")
    note = history.find { |m| m[:text].to_s.start_with?("[Office note]") }
    assert_match "breath_id: #{ui_card.id}", note[:text]
    assert_match "flyer_id: #{old_flyer.id}", note[:text]
  end

  test "the system prompt tells the model to use update_breath for flyers" do
    prompt = Ai::Office::SystemPrompt.build(briefing: "", user: @admin)
    assert_includes prompt, "update_breath"
    assert_includes prompt, "Never say you can't attach a flyer"
    assert_includes Ai::Office::Tools.definitions.map { |d| d[:name] }, "update_breath"
  end
end
