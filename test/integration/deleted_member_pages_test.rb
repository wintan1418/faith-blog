# frozen_string_literal: true

require "test_helper"

# When a member deletes their account, everything they touched must still
# render for everyone else: chats, notifications they caused, posts they
# commented on or liked, follows. (18 Nov: the inbox crashed after the App
# Review test account was deleted.)
class DeletedMemberPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { tour_completed_at: Time.current, welcomed_at: Time.current }
    @me = create_member("staying_member", **seen)
    @gone = create_member("leaving_member", **seen)
    @room = Room.create!(name: "Deletion Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @me, room: @room, title: "My breath", content: "Grace and peace",
                         status: :published, moderation_status: :approved)
    @their_post = Post.create!(user: @gone, room: @room, title: "Their breath", content: "Hello all",
                               status: :published, moderation_status: :approved)

    # Everything a member typically does to someone else.
    chat = Conversation.find_or_create_between!(@me, @gone)
    Message.create!(conversation: chat, sender: @gone, body: "Welcome home brother")
    Message.create!(conversation: chat, sender: @me, body: "Thank you")
    Comment.create!(post: @post, user: @gone, content: "Amen to this", moderation_status: :approved)
    Like.create!(user: @gone, likeable: @post, reaction_emoji: "🙏") rescue nil
    Follow.create!(follower: @gone, following: @me) rescue nil
    Follow.create!(follower: @me, following: @gone) rescue nil
    Notification.create!(user: @me, actor: @gone, notifiable: @post, notification_type: Notification.notification_types.keys.first)
    Notification.create!(user: @me, actor: @gone, notifiable: chat.messages.first, notification_type: :direct_message) rescue nil
    @chat = chat

    @gone.destroy!
  end

  PAGES = ->(t) {
    {
      "feed" => t.feed_path,
      "inbox" => t.conversations_path,
      "the old chat" => t.conversation_path(t.instance_variable_get(:@chat)),
      "notifications" => t.notifications_path,
      "my profile" => t.user_path(t.instance_variable_get(:@me).username),
      "my post" => t.post_path(t.instance_variable_get(:@post)),
      "the room" => t.room_path(t.instance_variable_get(:@room)),
      "following feed" => "/feed/following"
    }
  }

  test "every main page still opens after someone you interacted with deleted their account" do
    sign_in @me
    failures = PAGES.call(self).filter_map do |name, path|
      get path
      "#{name} (#{path}) → #{response.status}" if response.status >= 500
    end
    assert_empty failures, "these pages broke: #{failures.join(', ')}"
  end
end
