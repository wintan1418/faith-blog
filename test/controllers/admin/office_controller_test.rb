# frozen_string_literal: true

require "test_helper"

class Admin::OfficeControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["OFFICE_STUB"] = "1"
    @admin = create_member("office_admin_#{SecureRandom.hex(3)}", role: :admin)
    @member = create_member("office_member_#{SecureRandom.hex(3)}")
  end

  teardown { ENV.delete("OFFICE_STUB") }

  def conversation_for(user = @admin)
    user.office_conversations.create!(title: "Planning")
  end

  def breath_card(conversation, attrs = {})
    conversation.messages.create!(role: :tool, content: "{}", payload: {
      "tool_call_id" => "c1", "name" => "draft_breath", "result" => {},
      "card" => { "kind" => "breath", "status" => "draft", "title" => "", "body" => "Peace be with you all.", "prayer" => false }.merge(attrs)
    })
  end

  test "signed-out visitors and members can't reach the Office" do
    get admin_office_path
    assert_redirected_to new_user_session_path

    sign_in @member
    get admin_office_path
    assert_redirected_to root_path
    post admin_office_conversations_path, params: { message: { content: "Hi" } }
    assert_redirected_to root_path
    assert_equal 0, OfficeConversation.count
  end

  test "members can't act on cards or edit the briefing" do
    message = breath_card(conversation_for)
    sign_in @member
    assert_no_difference -> { Post.count } do
      post post_breath_admin_office_card_path(message)
    end
    assert_redirected_to root_path
    patch admin_office_briefing_path, params: { office_briefing: { body: "hijack" } }
    assert_redirected_to root_path
  end

  test "an admin sees the Office with the briefing pre-filled" do
    sign_in @admin
    get admin_office_path
    assert_response :success
    assert_match "What shall we work on?", response.body

    get admin_office_briefing_path
    assert_response :success
    assert_match "Juwon Oluwadare", response.body
  end

  test "starting a conversation saves the message and queues the reply" do
    sign_in @admin
    assert_enqueued_with(job: OfficeReplyJob) do
      post admin_office_conversations_path, params: { message: { content: "Draft a breath about hope" } }
    end
    conversation = @admin.office_conversations.last
    assert_redirected_to admin_office_conversation_path(conversation)
    assert_equal "Draft a breath about hope", conversation.title
    assert conversation.thinking?
    assert_equal [ "user" ], conversation.messages.map(&:role)
  end

  test "sending a message answers with turbo streams and the reply job runs end to end" do
    conversation = conversation_for
    sign_in @admin

    perform_enqueued_jobs do
      post admin_office_conversation_messages_path(conversation), params: { message: { content: "How many signed up this week?" } }, as: :turbo_stream
    end

    assert_response :success
    assert_match "office_composer", response.body
    assert_match %r{<textarea[^>]*>\s*</textarea>}, response.body, "the composer comes back empty"
    roles = conversation.reload.messages.map(&:role)
    assert_equal %w[user assistant tool assistant], roles
    assert_equal "site_stats", conversation.messages.tool.last.tool_name
    assert_not conversation.thinking?
  end

  test "an admin can't post into another admin's conversation" do
    other = create_member("other_admin_#{SecureRandom.hex(3)}", role: :admin)
    conversation = conversation_for(other)
    sign_in @admin
    post admin_office_conversation_messages_path(conversation), params: { message: { content: "Hi" } }
    assert_response :not_found
  end

  test "a second message waits while a reply is still being written" do
    conversation = conversation_for
    conversation.update!(thinking: true)
    sign_in @admin
    assert_no_enqueued_jobs(only: OfficeReplyJob) do
      post admin_office_conversation_messages_path(conversation), params: { message: { content: "Again" } }, as: :turbo_stream
    end
    assert_equal 0, conversation.messages.count
  end

  test "showing a conversation renders every kind of card" do
    conversation = conversation_for
    conversation.messages.create!(role: :user, content: "Hello")
    conversation.messages.create!(role: :assistant, content: "**Hello** back\n\n- one\n- two <script>alert(1)</script>")
    breath_card(conversation)
    broadcast = Broadcast.create!(sender: @admin, subject: "Thank you", body: "<p>Thank you for being part of Brethreign, truly.</p>")
    conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "draft_email", "card" => { "kind" => "email", "broadcast_id" => broadcast.id, "subject" => "Thank you" } })
    conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "draft_announcement", "card" => { "kind" => "announcement", "status" => "draft", "title" => "New games", "body" => "🎮 Games — Play together" } })
    conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "site_stats", "result" => { "members_total" => 3 } })

    sign_in @admin
    get admin_office_conversation_path(conversation)
    assert_response :success
    assert_match "<strong>Hello</strong>", response.body
    assert_no_match "<script>alert(1)</script>", response.body
    assert_match "Post now", response.body
    assert_match "Review and send on Broadcasts", response.body
    assert_match "Publish announcement", response.body
    assert_match "Checked the site numbers", response.body
  end

  test "Post now creates the breath as the admin and updates the card" do
    conversation = conversation_for
    message = breath_card(conversation)
    sign_in @admin

    assert_difference -> { Post.count }, 1 do
      post post_breath_admin_office_card_path(message), as: :turbo_stream
    end
    post = Post.order(:id).last
    assert_equal @admin, post.user
    assert post.published?
    assert_equal "posted", message.reload.card_data["status"]

    assert_no_difference -> { Post.count } do
      post post_breath_admin_office_card_path(message), as: :turbo_stream
    end
  end

  test "Schedule needs a future time and schedules the breath" do
    message = breath_card(conversation_for)
    sign_in @admin

    assert_no_difference -> { Post.count } do
      post post_breath_admin_office_card_path(message), params: { schedule_at: "2020-01-01T09:00" }, as: :turbo_stream
    end
    assert_match "future", message.reload.card_data["error"]

    at = 2.days.from_now.in_time_zone("Africa/Lagos").strftime("%Y-%m-%dT%H:%M")
    post post_breath_admin_office_card_path(message), params: { schedule_at: at }, as: :turbo_stream
    assert Post.order(:id).last.scheduled?
    assert_equal "scheduled", message.reload.card_data["status"]
  end

  test "Edit updates the breath card" do
    message = breath_card(conversation_for)
    room = Room.create!(name: "Testimonies #{SecureRandom.hex(2)}", description: "x", is_public: true)
    sign_in @admin
    patch update_breath_admin_office_card_path(message), params: { title: "Morning", body: "New words", room_id: room.id, prayer: "1" }, as: :turbo_stream
    card = message.reload.card_data
    assert_equal "New words", card["body"]
    assert_equal room.name, card["room_name"]
    assert card["prayer"]
  end

  test "Use in a breath starts a breath card with the flyer, which posts with the image" do
    conversation = conversation_for
    sign_in @admin
    Ai::Office::Providers::Stub.script(
      Ai::Office::Reply.new(tool_calls: [ { "id" => "f1", "name" => "generate_flyer", "input" => { "brief" => "Sunrise" } } ]),
      Ai::Office::Reply.new(text: "Done")
    )
    Ai::Office::Runner.new(conversation, provider: Ai::Office::Providers::Stub.new).run
    flyer = conversation.messages.tool.last

    post use_in_breath_admin_office_card_path(flyer), as: :turbo_stream
    card = conversation.messages.card.last
    assert_equal flyer.id, card.card_data["image_message_id"]

    patch update_breath_admin_office_card_path(card), params: { body: "Morning light." }, as: :turbo_stream
    post post_breath_admin_office_card_path(card), as: :turbo_stream
    assert Post.order(:id).last.images.attached?
  ensure
    Ai::Office::Providers::Stub.reset!
  end

  test "Publish announcement creates it" do
    conversation = conversation_for
    message = conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "draft_announcement", "card" => { "kind" => "announcement", "status" => "draft", "title" => "New games", "body" => "🎮 Games — Play together", "announcement_kind" => "release" } })
    sign_in @admin
    assert_difference -> { Announcement.count }, 1 do
      post publish_announcement_admin_office_card_path(message), as: :turbo_stream
    end
    assert_equal "published", message.reload.card_data["status"]
  end

  test "the briefing can be edited" do
    sign_in @admin
    patch admin_office_briefing_path, params: { office_briefing: { body: "Sign off as Wintan." } }
    assert_redirected_to admin_office_briefing_path
    assert_equal "Sign off as Wintan.", OfficeBriefing.current.body
    assert_equal @admin, OfficeBriefing.current.updated_by
  end

  test "importing notes starts a conversation with them as context" do
    sign_in @admin
    post import_admin_office_conversations_path, params: { title: "From Claude", notes: "We agreed the email subject." }
    conversation = @admin.office_conversations.last
    assert_redirected_to admin_office_conversation_path(conversation)
    assert_equal "From Claude", conversation.title
    assert conversation.messages.first.imported?
  end

  test "rename, retry and delete" do
    conversation = conversation_for
    sign_in @admin
    patch admin_office_conversation_path(conversation), params: { conversation: { title: "Launch emails" } }
    assert_equal "Launch emails", conversation.reload.title

    assert_enqueued_with(job: OfficeReplyJob) { post retry_admin_office_conversation_path(conversation), as: :turbo_stream }

    get refresh_admin_office_conversation_path(conversation), as: :turbo_stream
    assert_response :success

    delete admin_office_conversation_path(conversation)
    assert_redirected_to admin_office_path
    assert_not OfficeConversation.exists?(conversation.id)
  end
end
