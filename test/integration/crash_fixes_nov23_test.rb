# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Production issues from 23 Nov 2026: AI game rounds cut off mid-reply, a damaged
# stored picture breaking a page, and inbox counts that went stale (Trello).
class CrashFixesNov23Test < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include Turbo::Broadcastable::TestHelper

  setup do
    pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_badges", email: "ada-badges@example.com", password: pass, password_confirmation: pass)
    @ben = User.create!(username: "ben_badges", email: "ben-badges@example.com", password: pass, password_confirmation: pass)
    @cy  = User.create!(username: "cy_badges", email: "cy-badges@example.com", password: pass, password_confirmation: pass)
    @ada_ben = Conversation.find_or_create_between!(@ada, @ben)
    @ada_cy  = Conversation.find_or_create_between!(@ada, @cy)
  end

  def ai_reply(text)
    { "content" => [ { "type" => "text", "text" => text } ] }
  end

  VERSE_ROUND = {
    "questions" => [ { "prompt" => "Trust in the LORD with all thine ___", "choices" => %w[heart soul mind strength],
                       "correct_index" => 0, "reference" => "Proverbs 3:5", "explanation" => "KJV" } ]
  }.to_json

  # ── AI game rounds ──

  test "a verse-memory round asks for room and retries a cut-off reply" do
    calls = []
    fake = lambda do |system:, user:, images: [], max_tokens: nil|
      calls << max_tokens
      calls.size == 1 ? ai_reply('{"questions": [ {"prompt": "cut off') : ai_reply(VERSE_ROUND)
    end
    rows = Ai::Moderation::Client.stub(:call, fake) { Ai::Bible::VerseMemoryRound.call }

    assert_equal 1, rows.size
    assert_equal [ 2500, 2500 ], calls
  end

  test "a round that stays broken still reports the error after one retry" do
    calls = 0
    fake = ->(system:, user:, images: [], max_tokens: nil) { calls += 1; ai_reply("{ broken") }
    Ai::Moderation::Client.stub(:call, fake) do
      assert_raises(Ai::Bible::VerseMemoryRound::Error) { Ai::Bible::VerseMemoryRound.call }
    end
    assert_equal 2, calls
  end

  # ── Inbox counts ──

  test "a new message pushes fresh unread counts to the recipient's pages" do
    @ada_ben.messages.create!(sender: @ben, body: "Hello from Ben")
    assert_turbo_stream_broadcasts [ @ada, :badges ]

    @ada_cy.messages.create!(sender: @cy, body: "Hello from Cy")
    assert_equal 2, User.find(@ada.id).unread_conversations_count

    sign_in @ada
    get unread_counts_path, as: :json
    assert_equal 2, response.parsed_body["messages"]
  end

  test "every signed-in page carries the live badge element and its stream" do
    @ada_ben.messages.create!(sender: @ben, body: "Hello")
    sign_in @ada
    get conversations_path
    assert_select "#unread_counts[data-controller='live-badges'][data-live-badges-messages-value='1']"
    assert_select "turbo-cable-stream-source", minimum: 1
  end

  test "resting the pointer on a chat (Turbo prefetch) does not mark it read" do
    @ada_ben.messages.create!(sender: @ben, body: "Unread until opened")
    sign_in @ada

    get conversation_path(@ada_ben), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_response :success
    assert @ada_ben.reload.unread_for?(@ada)

    get conversation_path(@ada_ben)
    assert_not @ada_ben.reload.unread_for?(@ada)
  end

  test "inbox rows are never prefetched" do
    @ada_ben.messages.create!(sender: @ben, body: "Hi")
    sign_in @ada
    get conversations_path
    assert_select "##{dom_id(@ada_ben, :inbox_row)}[data-turbo-prefetch='false']"
  end

  # ── Damaged stored pictures ──

  test "a picture that fails its integrity check falls back to the original" do
    blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture_or_png, filename: "face.png", content_type: "image/png")
    variation = ActiveStorage::Variation.wrap(resize_to_fill: [ 100, 100 ]).key

    ActiveStorage::VariantWithRecord.stub_any_instance_processed_to_raise do
      get rails_blob_representation_path(blob.signed_id, variation, "face.png")
    end
    assert_response :redirect
    assert_no_match %r{/representations/}, response.location
  end

  private

  def file_fixture_or_png
    StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
  end
end

# Minimal "stub any instance" for the one call the representation controller makes.
class ActiveStorage::VariantWithRecord
  def self.stub_any_instance_processed_to_raise
    alias_method :__real_processed, :processed
    define_method(:processed) { raise ActiveStorage::IntegrityError }
    yield
  ensure
    alias_method :processed, :__real_processed
    remove_method :__real_processed
  end
end
