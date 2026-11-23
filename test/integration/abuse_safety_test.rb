# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Safety gaps from the November 2026 audit: blocks that hold everywhere, push
# endpoints that can't be aimed at our own network, uploads that only take
# photos, edits that get moderated again, chat files that go when deleted,
# rate limits on costly or spammy actions, and resources that wait for approval.
class AbuseSafetyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    @me = create_member("safe_me", welcomed_at: Time.current, tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @them = create_member("safe_them", welcomed_at: Time.current, tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    @room = Room.create!(name: "Safety Room", description: "x", room_type: :general, is_public: true)
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def complete_card(user)
    user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "A short profile for testing.",
                               occupation: "Builder", whatsapp_number: "+2348012345678", email: user.email)
  end

  def connect(a, b)
    ConnectionRequest.new(sender: a, receiver: b, status: :accepted).save!(validate: false)
  end

  def breath_by(user, title: "A breath", content: "Grace and peace to all of you here.")
    Post.create!(user: user, room: @room, title: title, content: content, status: :published,
                 moderation_status: :approved, allow_comments: true)
  end

  # --- M1: blocking ---------------------------------------------------------

  test "blocking removes the connection and follows both ways" do
    connect(@me, @them)
    @me.follow(@them)
    @them.follow(@me)

    sign_in @me
    post message_blocks_path(user_id: @them.id)

    assert_not ConnectionRequest.connected?(@me, @them)
    assert_not Follow.exists?(follower: @me, following: @them)
    assert_not Follow.exists?(follower: @them, following: @me)
  end

  test "a blocked member can't follow, connect or open the Brethren Card" do
    complete_card(@me)
    complete_card(@them)
    connect(@me, @them)
    MessageBlock.create!(blocker: @me, blocked: @them)
    assert_not ConnectionRequest.connected?(@me, @them)
    # Even if a connection somehow survived, the card stays shut.
    ConnectionRequest.insert!({ sender_id: @me.id, receiver_id: @them.id, status: 1, created_at: Time.current, updated_at: Time.current })

    sign_in @them
    post follow_user_path(@me.username)
    assert_not Follow.exists?(follower: @them, following: @me)

    ConnectionRequest.between(@me, @them)&.delete
    assert_no_difference -> { ConnectionRequest.count } do
      post connection_requests_path(receiver_id: @me.id)
    end
    assert_equal "You can't send a connection request to this member.", flash[:alert]

    get brethren_card_path(@me.username)
    assert_response :redirect
  end

  test "a blocked member can't comment on the blocker's breath and gets no alerts from them" do
    mine = breath_by(@me)
    MessageBlock.create!(blocker: @me, blocked: @them)

    sign_in @them
    assert_no_difference -> { Comment.count } do
      post post_comments_path(mine), params: { comment: { content: "Let me in" } }
    end

    # Likes and @mentions don't reach the blocker either.
    assert_no_difference -> { @me.notifications.count } do
      post likes_path(likeable_type: "Post", likeable_id: mine.id, reaction_type: "amen")
      breath_by(@them, content: "Hello @#{@me.username}, peace be with you all today.")
    end
  end

  test "the blocker can't comment on the blocked member's breath either" do
    theirs = breath_by(@them)
    MessageBlock.create!(blocker: @me, blocked: @them)
    sign_in @me
    assert_no_difference -> { Comment.count } do
      post post_comments_path(theirs), params: { comment: { content: "Hello there" } }
    end
  end

  test "after a declined request the sender has to wait a month to ask again" do
    complete_card(@me)
    complete_card(@them)
    request = ConnectionRequest.create!(sender: @me, receiver: @them)
    request.update!(status: :declined)

    sign_in @me
    post connection_requests_path(receiver_id: @them.id)
    assert_predicate request.reload, :declined?
    assert_match "You can ask again after", flash[:alert]

    request.update_columns(updated_at: 31.days.ago)
    post connection_requests_path(receiver_id: @them.id)
    assert_predicate request.reload, :pending?
  end

  # --- M2 / L3: push ---------------------------------------------------------

  test "push subscriptions only accept real browser push services" do
    sign_in @me
    keys = { p256dh: "BKey", auth: "auth" }
    %w[http://fcm.googleapis.com/fcm/send/x https://169.254.169.254/latest https://localhost/x
       https://evil.example/fcm.googleapis.com https://fcm.googleapis.com.evil.example/x].each do |bad|
      post push_subscriptions_path, params: { endpoint: bad, keys: keys }, as: :json
      assert_response :unprocessable_entity, bad
    end
    assert_equal 0, PushSubscription.count

    %w[https://fcm.googleapis.com/fcm/send/abc https://updates.push.services.mozilla.com/wpush/v2/abc
       https://web.push.apple.com/QAbc https://wns2-par02p.notify.windows.com/w/?token=abc].each do |good|
      post push_subscriptions_path, params: { endpoint: good, keys: keys }, as: :json
      assert_response :success, good
    end
  end

  test "someone else's push endpoint isn't moved to a new account without its keys" do
    sub = @them.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/theirs", p256dh_key: "theirP", auth_key: "theirA")
    sign_in @me
    post push_subscriptions_path, params: { endpoint: sub.endpoint, keys: { p256dh: "mine", auth: "mine" } }, as: :json
    assert_response :conflict
    assert_equal @them, sub.reload.user

    # The same browser (same keys) signing in as someone else does move it.
    post push_subscriptions_path, params: { endpoint: sub.endpoint, keys: { p256dh: "theirP", auth: "theirA" } }, as: :json
    assert_response :success
    assert_equal @me, sub.reload.user
  end

  test "a stored subscription with a bad endpoint is never posted to" do
    sub = @me.push_subscriptions.new(endpoint: "http://10.0.0.1/x", p256dh_key: "a", auth_key: "b")
    sub.save!(validate: false)
    called = false
    WebPush.stub(:payload_send, ->(**) { called = true }) do
      assert_equal false, sub.deliver(title: "t", body: "b")
    end
    assert_not called
  end

  # --- M6: uploads --------------------------------------------------------------

  test "direct uploads need a member, a photo and a sensible size" do
    blob = { filename: "x.png", byte_size: 1000, checksum: Digest::MD5.base64digest("x"), content_type: "image/png" }
    post rails_direct_uploads_path, params: { blob: blob }, as: :json
    assert_response :unauthorized

    sign_in @me
    post rails_direct_uploads_path, params: { blob: blob.merge(filename: "x.zip", content_type: "application/zip") }, as: :json
    assert_response :unprocessable_entity
    post rails_direct_uploads_path, params: { blob: blob.merge(byte_size: 50.megabytes) }, as: :json
    assert_response :unprocessable_entity

    post rails_direct_uploads_path, params: { blob: blob }, as: :json
    assert_response :success
    assert JSON.parse(response.body)["signed_id"].present?
  end

  # --- M4: edits are moderated again ---------------------------------------------

  test "editing a breath into a scam holds or blocks it" do
    mine = breath_by(@me)
    AiModerationReview.from_result(reviewable: mine, user: @me, result: Ai::Moderation::Result.trusted_skip)

    sign_in @me
    perform_enqueued_jobs(only: AiModerationGateJob) do
      patch post_path(mine), params: { post: { content: "Double your money with my forex plan, just send me money now" } }
    end
    assert_not mine.reload.moderation_approved?, "edited breath stayed live"
  end

  test "a harmless edit leaves a breath live" do
    mine = breath_by(@me)
    AiModerationReview.from_result(reviewable: mine, user: @me, result: Ai::Moderation::Result.trusted_skip)
    sign_in @me
    perform_enqueued_jobs(only: AiModerationGateJob) do
      patch post_path(mine), params: { post: { content: "Grace and peace, edited with a kinder word for everyone." } }
    end
    assert mine.reload.moderation_approved?
  end

  test "editing a comment into a scam hides it" do
    theirs = breath_by(@them)
    comment = Comment.create!(post: theirs, user: @me, content: "Amen to this", moderation_status: :approved)
    sign_in @me
    patch post_comment_path(theirs, comment), params: { comment: { content: "Double your money with forex, send me money" } }
    assert_not comment.reload.moderation_approved?
  end

  test "editing a message re-runs moderation without a second alert" do
    conversation = Conversation.find_or_create_between!(@me, @them)
    message = conversation.messages.create!(sender: @me, body: "Hello friend, how are you today?")
    assert_not message.reload.removed?

    sign_in @me
    assert_no_difference -> { @them.notifications.count } do
      patch conversation_message_path(conversation, message), params: { message: { body: "Send me money, I need your bank details and otp" } }
    end
    assert message.reload.removed?, "edited scam message stayed up"
  end

  # --- M3: chat files --------------------------------------------------------------

  test "deleting a message deletes its files, but not ones a forwarded copy still uses" do
    conversation = Conversation.find_or_create_between!(@me, @them)
    message = conversation.messages.create!(sender: @me, body: "files")
    message.documents.attach(io: StringIO.new("%PDF-1.4 a"), filename: "a.pdf", content_type: "application/pdf")
    message.voice_note.attach(io: StringIO.new("OggS"), filename: "v.ogg", content_type: "audio/ogg")
    shared_doc = message.documents.first.blob
    voice_blob = message.voice_note.blob
    other = Conversation.find_or_create_between!(@me, create_member("safe_third"))
    message.forward_to(other, by: @me)

    sign_in @me
    perform_enqueued_jobs do
      delete conversation_message_path(conversation, message)
    end
    assert_not message.reload.documents.attached?
    assert_not message.voice_note.attached?
    assert ActiveStorage::Blob.exists?(shared_doc.id), "the forwarded copy lost its file"
    assert ActiveStorage::Blob.exists?(voice_blob.id), "voice note was forwarded too, so it stays"

    lonely = conversation.messages.create!(sender: @me, body: "one more")
    lonely.images.attach(io: file_fixture_or_png, filename: "p.png", content_type: "image/png")
    blob = lonely.images.first.blob
    perform_enqueued_jobs { delete conversation_message_path(conversation, lonely) }
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "voice notes play through the members-only file route, with byte ranges" do
    conversation = Conversation.find_or_create_between!(@me, @them)
    message = conversation.messages.new(sender: @them, body: "")
    message.voice_note.attach(io: StringIO.new("OggS0123456789"), filename: "v.ogg", content_type: "audio/ogg")
    message.save!

    sign_in @me
    get conversation_path(conversation)
    path = conversation_message_file_path(conversation, message, message.voice_note.id, filename: "v.ogg", inline: 1)
    assert_select "audio.msg-voice[src=?]", path
    assert_no_match %r{rails/active_storage/[^"]*v\.ogg"[^>]*data-voice}, response.body

    get path, headers: { "Range" => "bytes=0-3" }
    assert_response :partial_content
    assert_equal "OggS", response.body

    sign_in create_member("safe_outsider")
    get path
    assert_response :not_found
  end

  # --- M7: rate limits --------------------------------------------------------------

  test "AI helpers answer kindly in JSON once the hourly budget is spent" do
    sign_in @me
    40.times { post check_gentleness_posts_path, params: { text: "short" }, as: :json }
    post check_gentleness_posts_path, params: { text: "short" }, as: :json
    assert_response :too_many_requests
    assert_equal false, JSON.parse(response.body)["ok"]
  end

  test "game rounds share one generate budget" do
    sign_in @me
    60.times { post games_quiz_generate_path, as: :json }
    post games_pic_word_generate_path, as: :json
    assert_response :too_many_requests
  end

  test "comment floods are slowed with a friendly message" do
    theirs = breath_by(@them)
    sign_in @me
    10.times { |i| post post_comments_path(theirs), params: { comment: { content: "Amen number #{i}" } } }
    assert_no_difference -> { Comment.count } do
      post post_comments_path(theirs), params: { comment: { content: "One too many" } }
    end
    assert_match "doing that a lot", flash[:alert]
  end

  test "direct messages, likes, connection requests and giving are limited" do
    conversation = Conversation.find_or_create_between!(@me, @them)
    connect(@me, @them)
    sign_in @me
    30.times { |i| post conversation_messages_path(conversation), params: { message: { body: "hi #{i}" } } }
    assert_no_difference -> { Message.count } do
      post conversation_messages_path(conversation), params: { message: { body: "flood" } }
    end

    theirs = breath_by(@them)
    60.times { post likes_path(likeable_type: "Post", likeable_id: theirs.id, reaction_type: "amen") }
    post likes_path(likeable_type: "Post", likeable_id: theirs.id, reaction_type: "amen"), as: :turbo_stream
    assert_response :too_many_requests

    30.times { post connection_requests_path(receiver_id: @them.id) }
    post connection_requests_path(receiver_id: @them.id), as: :turbo_stream
    assert_response :too_many_requests

    sign_out @me
    ENV["DONATIONS_PUBLIC"] = "1"
    10.times { post give_path, params: { donation: { amount: 1000 } } }
    post give_path, params: { donation: { amount: 1000 } }
    assert_response :see_other
    assert_match "doing that a lot", flash[:alert]
  ensure
    ENV.delete("DONATIONS_PUBLIC")
  end

  test "an invitation can be resent once a day" do
    sign_in @me
    post invitations_path, params: { invitation: { email: "friend@example.com" } }
    invitation = @me.sent_invitations.find_by!(email: "friend@example.com")

    assert_no_enqueued_emails do
      post resend_invitation_path(invitation)
      post invitations_path, params: { invitation: { email: "friend@example.com" } }
    end
    assert_match "tomorrow", flash[:alert]

    invitation.update_columns(last_sent_at: 25.hours.ago)
    assert_enqueued_emails 1 do
      post resend_invitation_path(invitation)
    end
  end

  # --- L6: resources -------------------------------------------------------------------

  test "unapproved resources are hidden by slug, and editing an approved one sends it back for approval" do
    category = ResourceCategory.create!(name: "Study #{SecureRandom.random_number(10**6).to_s.rjust(6, "0")}")
    resource = Resource.create!(user: @me, resource_category: category, title: "Pending guide", resource_type: :link, url: "https://example.com/a")

    get resources_item_path(resource)
    assert_response :not_found
    sign_in @them
    get resources_item_path(resource)
    assert_response :not_found
    sign_in @me
    get resources_item_path(resource)
    assert_response :success

    resource.update!(approved: true, approved_at: Time.current)
    patch resources_item_path(resource), params: { resource: { url: "https://spam.example/b" } }
    assert_not resource.reload.approved?
    sign_in @them
    get resources_item_path(resource)
    assert_response :not_found
  end

  test "portfolio pieces stay private with a private profile" do
    @me.profile || @me.create_profile!
    @me.profile.update_columns(public_profile: false)
    item = @me.portfolio_items.new(title: "My work", category: PortfolioItem::CATEGORIES.keys.first)
    item.save!(validate: false)

    get portfolio_work_path(@me.username, item)
    assert_response :not_found
    sign_in @them
    get portfolio_work_path(@me.username, item)
    assert_response :not_found
  end

  private

  def file_fixture_or_png
    StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
  end
end
