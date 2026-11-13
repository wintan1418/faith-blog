# frozen_string_literal: true

require "test_helper"

class ConnectionRequestsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Turbo::Broadcastable::TestHelper

  setup do
    @sender = create_user("sender")
    @receiver = create_user("receiver")
    complete_card(@sender)
    complete_card(@receiver)

    sign_in @sender
  end

  test "connection request creates and updates action target over turbo stream" do
    post connection_requests_path(receiver_id: @receiver.id), as: :turbo_stream

    assert_response :success
    assert @sender.sent_connection_requests.pending.exists?(receiver: @receiver)
    assert_includes response.body, dom_id(@receiver, :connection_actions)
    assert_includes response.body, "Request Sent"
  end

  test "incomplete brethren card shows clear turbo response instead of silent no-op" do
    @sender.brethren_card.update_columns(church_or_assembly: nil, is_complete: false)

    post connection_requests_path(receiver_id: @receiver.id), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_not @sender.sent_connection_requests.exists?(receiver: @receiver)
    assert_includes response.body, dom_id(@receiver, :connection_actions)
    assert_includes response.body, "Complete Brethren Card"
  end

  test "accepting request updates connection action target" do
    request = ConnectionRequest.create!(sender: @sender, receiver: @receiver)
    sign_in @receiver

    post accept_connection_request_path(request), as: :turbo_stream

    assert_response :success
    assert request.reload.accepted?
    assert_includes response.body, dom_id(@sender, :connection_actions)
    assert_includes response.body, "connection_requests_received"
    assert_includes response.body, "No pending requests."
    assert_includes response.body, "Brethren Card"
  end

  test "the requests page is never served from Turbo's snapshot cache and listens for changes" do
    get connection_requests_path

    assert_response :success
    assert_select "meta[name='turbo-cache-control'][content='no-cache']", count: 1
    assert_select "turbo-cable-stream-source", minimum: 1
    assert_select "#connection_requests_received"
    assert_select "#connection_requests_sent"
  end

  test "accepting a request (e.g. from the sender's profile) updates both open requests pages live" do
    request = ConnectionRequest.create!(sender: @sender, receiver: @receiver)

    receiver_streams = capture_turbo_stream_broadcasts([ @receiver, :connection_requests ]) do
      sender_streams = capture_turbo_stream_broadcasts([ @sender, :connection_requests ]) do
        request.update!(status: :accepted)
      end
      sent = sender_streams.select { |s| s["target"] == "connection_requests_sent" }.last
      assert sent, "no update for the sender's Sent Requests"
      assert_includes sent.to_html, "Accepted"
    end

    received = receiver_streams.select { |s| s["target"] == "connection_requests_received" }.last
    assert received, "no update for the receiver's Received Requests"
    assert_equal "replace", received["action"]
    assert_includes received.to_html, "No pending requests."
  end

  test "a new request shows up on the receiver's open requests page" do
    streams = capture_turbo_stream_broadcasts([ @receiver, :connection_requests ]) do
      ConnectionRequest.create!(sender: @sender, receiver: @receiver)
    end

    received = streams.find { |s| s["target"] == "connection_requests_received" }
    assert received
    assert_includes received.to_html, @sender.display_name
  end

  private

  def create_user(username)
    User.create!(
      username: username,
      email: "#{username}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def complete_card(user)
    user.brethren_card.update!(
      church_or_assembly: "Grace Assembly",
      bio: "A short profile for connection testing.",
      occupation: "Builder",
      whatsapp_number: "+2348012345678",
      email: user.email
    )
  end
end
