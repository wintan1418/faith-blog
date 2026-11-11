# frozen_string_literal: true

require "test_helper"

# Checks the request each provider builds from the Office's history, without
# touching the network.
class Ai::Office::ProvidersTest < ActiveSupport::TestCase
  HISTORY = [
    { role: :user, text: "How many joined?" },
    { role: :assistant, text: "Checking.", tool_calls: [
      { "id" => "t1", "name" => "site_stats", "input" => { "days" => 7 } },
      { "id" => "t2", "name" => "recent_activity", "input" => { "kind" => "users" } }
    ] },
    { role: :tool, tool_call_id: "t1", name: "site_stats", result: { "members_total" => 10 } },
    { role: :tool, tool_call_id: "t2", name: "recent_activity", result: { "error" => "nope" } }
  ].freeze
  TOOLS = [ { name: "site_stats", description: "Numbers", parameters: { type: "object", properties: {} } } ].freeze

  def capture(provider, response, history: HISTORY)
    sent = nil
    provider.define_singleton_method(:post_json) do |_uri, body:, **|
      sent = body
      response
    end
    reply = provider.chat(system: "System", messages: history, tools: TOOLS)
    [ sent, reply ]
  end

  test "anthropic groups tool results into one user turn and reads tool_use blocks" do
    provider = Ai::Office::Providers::Anthropic.new(api_key: "k")
    body, reply = capture(provider, {
      "model" => "claude-opus-5-5", "stop_reason" => "tool_use",
      "content" => [ { "type" => "thinking", "thinking" => "", "signature" => "sig" },
                     { "type" => "text", "text" => "One moment." },
                     { "type" => "tool_use", "id" => "t3", "name" => "site_stats", "input" => { "days" => 30 } } ]
    })

    assert_equal "claude-opus-5-5", body[:model]
    assert_equal %w[user assistant user], body[:messages].map { |m| m[:role] }
    results = body[:messages].last[:content]
    assert_equal %w[t1 t2], results.map { |b| b[:tool_use_id] }
    assert results.last[:is_error]
    assert_equal "site_stats", body[:tools].first[:name]
    assert_equal "medium", body.dig(:output_config, :effort)

    assert_equal "One moment.", reply.text
    assert_equal [ { "id" => "t3", "name" => "site_stats", "input" => { "days" => 30 } } ], reply.tool_calls
    assert_equal "thinking", reply.raw["content"].first["type"], "thinking blocks are kept for replay"
  end

  test "anthropic replays its own raw content unchanged" do
    provider = Ai::Office::Providers::Anthropic.new(api_key: "k")
    raw = [ { "type" => "thinking", "thinking" => "", "signature" => "sig" }, { "type" => "text", "text" => "Hi" } ]
    history = [ { role: :user, text: "Hi" }, { role: :assistant, text: "Hi", tool_calls: [], raw: { "provider" => "anthropic", "model" => provider.model, "content" => raw } }, { role: :user, text: "Again" } ]
    sent, = capture(provider, { "content" => [] }, history: history)
    assert_equal raw, sent[:messages][1][:content]
  end

  test "openai sends function tools and tool messages" do
    provider = Ai::Office::Providers::Openai.new(api_key: "k")
    body, reply = capture(provider, {
      "model" => "gpt-5.5",
      "choices" => [ { "finish_reason" => "tool_calls", "message" => { "content" => nil, "tool_calls" => [
        { "id" => "c9", "type" => "function", "function" => { "name" => "site_stats", "arguments" => "{\"days\":7}" } }
      ] } } ]
    })

    assert_equal "system", body[:messages].first[:role]
    assert_equal %w[system user assistant tool tool], body[:messages].map { |m| m[:role] }
    assert_equal "function", body[:tools].first[:type]
    assert_equal [ { "id" => "c9", "name" => "site_stats", "input" => { "days" => 7 } } ], reply.tool_calls
  end

  test "openai falls back to the next model when the default isn't available" do
    provider = Ai::Office::Providers::Openai.new(api_key: "k")
    tried = []
    provider.define_singleton_method(:post_json) do |_uri, body:, **|
      tried << body[:model]
      raise Ai::Office::Client::ApiError.new("The model `gpt-5.5` does not exist", status: 404) if tried.size == 1

      { "model" => body[:model], "choices" => [ { "message" => { "content" => "Hi" } } ] }
    end

    reply = provider.chat(system: "S", messages: [ { role: :user, text: "Hi" } ], tools: TOOLS)
    assert_equal [ "gpt-5.5", "gpt-5.1" ], tried
    assert_equal "Hi", reply.text
  end

  test "gemini sends function declarations and function responses" do
    provider = Ai::Office::Providers::Gemini.new(api_key: "k")
    body, reply = capture(provider, {
      "candidates" => [ { "content" => { "parts" => [ { "functionCall" => { "name" => "site_stats", "args" => { "days" => 7 } } } ] } } ]
    })

    assert_equal %w[user model user], body[:contents].map { |c| c[:role] }
    assert_equal 2, body[:contents].last[:parts].size
    assert_equal "site_stats", reply.tool_calls.first["name"]
  end

  test "client prefers anthropic, then openai, then gemini, and stubs in tests" do
    keys = %w[ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY OFFICE_PROVIDER OFFICE_STUB AI_MODERATION_STUB]
    saved = keys.index_with { |k| ENV[k] }
    keys.each { |k| ENV.delete(k) }

    assert_equal "stub", Ai::Office::Client.provider_name
    ENV["GEMINI_API_KEY"] = "g"
    assert_equal "gemini", Ai::Office::Client.provider_name
    ENV["OPENAI_API_KEY"] = "o"
    assert_equal "openai", Ai::Office::Client.provider_name
    ENV["ANTHROPIC_API_KEY"] = "a"
    assert_equal "anthropic", Ai::Office::Client.provider_name
    ENV["OFFICE_PROVIDER"] = "openai"
    assert_equal "openai", Ai::Office::Client.provider_name
    ENV["OFFICE_STUB"] = "1"
    assert_equal "stub", Ai::Office::Client.provider_name
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
