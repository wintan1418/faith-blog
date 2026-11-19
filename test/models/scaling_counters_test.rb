# frozen_string_literal: true

require "test_helper"

# Cheap counters: the inbox badge and post view counts.
class ScalingCountersTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @ada = make_user("count_ada")
    @ben = make_user("count_ben")
  end

  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: "password123")
  end

  def fresh(user) = User.find(user.id)

  test "unread badge matches the inbox: deleted messages and archived chats don't count" do
    chat = Conversation.find_or_create_between!(@ada, @ben)
    msg = chat.messages.create!(sender: @ben, body: "Hello there")
    assert_equal 1, fresh(@ada).unread_conversations_count
    assert_equal 0, fresh(@ben).unread_conversations_count, "your own messages aren't unread"

    msg.update_columns(deleted_at: Time.current)
    assert_equal 0, fresh(@ada).unread_conversations_count

    chat.messages.create!(sender: @ben, body: "Are you there?")
    assert_equal 1, fresh(@ada).unread_conversations_count
    chat.conversation_participants.find_by(user: @ada).update!(archived_at: Time.current)
    assert_equal 0, fresh(@ada).unread_conversations_count

    chat.conversation_participants.find_by(user: @ada).update!(archived_at: nil, last_read_at: 1.second.from_now)
    assert_equal 0, fresh(@ada).unread_conversations_count
  end

  test "unread badge stops counting at the cap" do
    stub_cap(2) do
      3.times do |i|
        other = make_user("count_friend#{i}")
        Conversation.find_or_create_between!(@ada, other).messages.create!(sender: other, body: "Hi #{i}")
      end
      assert_equal 2, fresh(@ada).unread_conversations_count
    end
  end

  test "a post view counts once per viewer per hour" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    room = Room.create!(name: "Views Room", description: "x", room_type: :general, is_public: true)
    post = Post.create!(user: @ada, room: room, title: "Counted once", content: "x", status: :published)

    assert post.record_view!("u#{@ben.id}")
    refute post.record_view!("u#{@ben.id}")
    assert post.record_view!("ip123")
    assert_equal 2, post.reload.views_count

    travel Post::VIEW_WINDOW + 1.minute do
      assert post.record_view!("u#{@ben.id}")
    end
    assert_equal 3, post.reload.views_count
  ensure
    Rails.cache = original_cache
  end

  private

  def stub_cap(value)
    original = User::UNREAD_CONVERSATIONS_CAP
    silence_warnings { User.const_set(:UNREAD_CONVERSATIONS_CAP, value) }
    yield
  ensure
    silence_warnings { User.const_set(:UNREAD_CONVERSATIONS_CAP, original) }
  end
end
