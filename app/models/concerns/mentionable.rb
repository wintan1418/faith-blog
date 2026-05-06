# frozen_string_literal: true

module Mentionable
  extend ActiveSupport::Concern

  included do
    has_many :mentions, as: :mentionable, dependent: :destroy
    has_many :mentioned_users, through: :mentions, source: :user
  end

  # Extract usernames from content
  def extract_mentions
    # Get HTML content first (ActionText stores as HTML)
    html_content = if respond_to?(:content) && content.present?
      # ActionText content - get the HTML
      if content.is_a?(ActionText::Content)
        content.to_s
      else
        content.to_s
      end
    elsif respond_to?(:body) && body.present?
      body.to_s
    elsif respond_to?(:content)
      content.to_s
    else
      ""
    end

    return [] if html_content.blank?

    # Extract mentions from HTML (they can be in text nodes or HTML)
    # First, get plain text version
    plain_text = if respond_to?(:content) && content.present? && content.respond_to?(:to_plain_text)
      content.to_plain_text
    else
      # Strip HTML tags manually
      html_content.gsub(/<[^>]+>/, " ")
    end

    # Extract from HTML (mentions might be in HTML like <div>@username</div>)
    html_mentions = html_content.scan(/@([a-zA-Z0-9_-]{3,30})/).flatten.uniq

    # Extract from plain text (in case they're in text nodes)
    plain_mentions = plain_text.scan(/@([a-zA-Z0-9_-]{3,30})/).flatten.uniq

    # Combine and return unique mentions
    (html_mentions + plain_mentions).uniq
  end

  # Process mentions and create Mention records
  def process_mentions!(mentioned_by_user)
    return [] unless mentioned_by_user.present?

    raw_tokens = extract_mentions.map(&:downcase).uniq
    has_everyone = raw_tokens.include?("everyone")
    has_all      = raw_tokens.include?("all")
    usernames    = raw_tokens - %w[everyone all here]

    mentions.where.not(user_id: User.where("LOWER(username) IN (?)", usernames).select(:id)).destroy_all if usernames.any?

    mentioned_users = usernames.any? ? User.where("LOWER(username) IN (?)", usernames) : User.none
    created_mentions = []

    mentioned_users.each do |user|
      next if user == mentioned_by_user

      mention = mentions.find_or_initialize_by(user: user)
      mention.mentioned_by = mentioned_by_user
      mention.save! if mention.new_record? || mention.changed?

      created_mentions << mention

      existing_notification = Notification.where(
        user: user,
        actor: mentioned_by_user,
        notifiable: self,
        notification_type: :mentioned
      ).where("created_at > ?", 1.hour.ago).first

      unless existing_notification
        Notification.create(
          user: user,
          actor: mentioned_by_user,
          notifiable: self,
          notification_type: :mentioned
        )
      end
    end

    fanout_everyone_mention!(mentioned_by_user) if has_everyone
    fanout_platform_mention!(mentioned_by_user) if has_all && mentioned_by_user.respond_to?(:super_admin?) && mentioned_by_user.super_admin?

    created_mentions
  end

  # @everyone — notify all members of the breath's room (or post's room for comments).
  # Anyone in the room can use it. Soft rate limit: 1 per author per room per 24h.
  def fanout_everyone_mention!(actor)
    room = mention_target_room
    return unless room

    cooldown = Notification.where(
      actor: actor,
      notification_type: :everyone_mention,
      notifiable: self
    ).where("created_at > ?", 24.hours.ago).exists?
    return if cooldown

    target_user_ids = (room.respond_to?(:members) ? room.members.where.not(id: actor.id).pluck(:id) : User.where.not(id: actor.id).pluck(:id))
    create_everyone_notifications(target_user_ids, actor)
  end

  # @all — super_admin only — notify every active platform user.
  # Cached cap: 1 platform-wide broadcast per super_admin per 24 hours.
  def fanout_platform_mention!(actor)
    cache_key = "platform_mention:#{actor.id}"
    return if Rails.cache.exist?(cache_key)
    Rails.cache.write(cache_key, true, expires_in: 24.hours)

    scope = User.respond_to?(:active) ? User.active : User.all
    target_user_ids = scope.where.not(id: actor.id).pluck(:id)
    create_everyone_notifications(target_user_ids, actor, scope: "platform")
  end

  def mention_target_room
    return room if respond_to?(:room) && room.present?
    return post.room if respond_to?(:post) && post&.room.present?

    nil
  end

  def create_everyone_notifications(user_ids, actor, scope: "room")
    return if user_ids.blank?

    rows = user_ids.map do |uid|
      {
        user_id:           uid,
        actor_id:          actor.id,
        notifiable_type:   self.class.name,
        notifiable_id:     id,
        notification_type: Notification.notification_types[:everyone_mention],
        created_at:        Time.current,
        updated_at:        Time.current
      }
    end

    Notification.insert_all(rows)
  end

  # Get content with mentions as links (for ActionText, returns HTML)
  def content_with_mentions
    raw = if respond_to?(:content) && content.present?
            content.to_s
          else
            content.to_s
          end

    raw.gsub(/@([a-zA-Z0-9_-]{2,30})/) do |match|
      handle = $1.downcase
      case handle
      when "everyone"
        %(<span class="mention-broadcast" data-scope="room">@everyone</span>)
      when "all"
        %(<span class="mention-broadcast mention-broadcast-platform" data-scope="platform">@all</span>)
      else
        user = User.find_by("LOWER(username) = ?", handle)
        if user
          %(<a href="/u/#{user.username}" class="mention-link">@#{user.username}</a>)
        else
          match
        end
      end
    end.html_safe
  end
end
