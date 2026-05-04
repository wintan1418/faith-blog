# frozen_string_literal: true

module MentionsHelper
  # Render content with mentions highlighted
  # For ActionText, we need to process the HTML output
  def render_with_mentions(content)
    return "" if content.blank?

    # Get HTML content (works for both ActionText and regular text)
    html = if content.is_a?(ActionText::Content)
      content.to_s
    elsif content.respond_to?(:to_s)
      content.to_s
    else
      ""
    end

    return "" if html.blank?

    # Process mentions in text content only (not inside HTML tag attributes)
    # Split HTML into parts: tags and text content
    result = ""
    i = 0
    while i < html.length
      if html[i] == "<"
        # Find the end of the tag
        tag_end = html.index(">", i)
        if tag_end
          # Add the entire tag as-is
          result += html[i..tag_end]
          i = tag_end + 1
        else
          result += html[i]
          i += 1
        end
      else
        # Find the start of the next tag or end of string
        next_tag = html.index("<", i)
        text_content = next_tag ? html[i...next_tag] : html[i..-1]

        # Process mentions in this text content
        processed_text = text_content.gsub(/@([a-zA-Z0-9_-]{3,30})/) do |match|
          username = $1
          user = User.find_by(username: username)
          if user
            %(<a href="#{user_path(user)}" class="mention-link text-blue-600 dark:text-blue-400 hover:underline font-medium">@#{username}</a>)
          else
            match
          end
        end

        result += processed_text
        i = next_tag || html.length
      end
    end

    result.html_safe
  end

  # Get list of mentioned users for display
  def mentioned_users_for(mentionable)
    mentionable.mentioned_users if mentionable.respond_to?(:mentioned_users)
  end
end
