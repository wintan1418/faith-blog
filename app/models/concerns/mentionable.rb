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
      html_content.gsub(/<[^>]+>/, ' ')
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
    
    usernames = extract_mentions
    return [] if usernames.empty?

    mentioned_users = User.where(username: usernames)
    created_mentions = []

    mentioned_users.each do |user|
      # Skip if user mentioned themselves
      next if user == mentioned_by_user

      # Remove old mentions for this user to avoid duplicates
      mentions.where(user: user).destroy_all

      # Create new mention
      mention = mentions.create(
        user: user,
        mentioned_by: mentioned_by_user
      )

      created_mentions << mention

      # Create notification for mentioned user (only if not already notified recently)
      existing_notification = Notification.where(
        user: user,
        actor: mentioned_by_user,
        notifiable: self,
        notification_type: :mentioned
      ).where('created_at > ?', 1.hour.ago).first

      unless existing_notification
        Notification.create(
          user: user,
          actor: mentioned_by_user,
          notifiable: self,
          notification_type: :mentioned
        )
      end
    end

    created_mentions
  end

  # Get content with mentions as links (for ActionText, returns HTML)
  def content_with_mentions
    if respond_to?(:content) && content.present?
      # For ActionText, we need to process the HTML
      html_content = content.to_s
      
      # Replace @username with links in HTML
      html_content.gsub(/@([a-zA-Z0-9_-]{3,30})/) do |match|
        username = $1
        user = User.find_by(username: username)
        if user
          %(<a href="/u/#{user.username}" class="mention-link text-blue-600 dark:text-blue-400 hover:underline font-medium">@#{username}</a>)
        else
          match
        end
      end.html_safe
    elsif respond_to?(:content)
      # Regular text content
      text = content.to_s
      text.gsub(/@([a-zA-Z0-9_-]{3,30})/) do |match|
        username = $1
        user = User.find_by(username: username)
        if user
          %(<a href="/u/#{user.username}" class="mention-link text-blue-600 dark:text-blue-400 hover:underline font-medium">@#{username}</a>)
        else
          match
        end
      end.html_safe
    else
      ""
    end
  end
end

