# frozen_string_literal: true

require "cgi"

module MentionsHelper
  SOCIAL_TOKEN_REGEX = %r{https?://[^\s<]+|(?<![\w@])@[a-zA-Z0-9_]{3,30}}

  # Render user-authored post/comment text the way social apps do:
  # blank lines create paragraphs, single line breaks stay visible, URLs
  # and mentions are linked, and unsafe markup is escaped.
  def render_social_text(content, class_name: nil, paragraph_class: nil, data: nil)
    text = social_plain_text(content)
    return "" if text.blank?

    users_by_username = social_mentioned_users(text)
    paragraphs = text.split(/\n{2,}/).map do |paragraph|
      lines = paragraph.split(/\n/, -1)
      children = lines.each_with_index.flat_map do |line, index|
        nodes = social_inline_nodes(line, users_by_username)
        index.zero? ? nodes : [ tag.br, *nodes ]
      end

      tag.p(safe_join(children), class: paragraph_class)
    end

    tag.div(safe_join(paragraphs), class: class_name, data: data)
  end

  def render_social_card_text(content, class_name: nil, data: nil)
    text = social_plain_text(content)
    return "" if text.blank?

    users_by_username = social_mentioned_users(text)
    children = text.split(/\n{2,}/).each_with_index.flat_map do |paragraph, paragraph_index|
      nodes = social_inline_paragraph_nodes(paragraph, users_by_username)
      paragraph_index.zero? ? nodes : [ tag.br, tag.br, *nodes ]
    end

    tag.div(safe_join(children), class: class_name, data: data)
  end

  # Backwards-compatible name used by older views.
  def render_with_mentions(content)
    render_social_text(content)
  end

  # Get list of mentioned users for display
  def mentioned_users_for(mentionable)
    mentionable.mentioned_users if mentionable.respond_to?(:mentioned_users)
  end

  private

  # Rich rendering for the post page: KEEPS the author's Trix formatting
  # (bold, italics, headings, lists, quotes) — render_social_text flattens
  # everything to plain text, which silently erased all formatting — while
  # still linkifying @mentions and bare URLs inside the text nodes.
  def render_rich_social_text(content, class_name: nil, data: nil)
    html = content.respond_to?(:body) ? content.body&.to_html : content.to_s
    return "" if html.blank?

    clean = sanitize(html)
    users_by_username = social_mentioned_users(social_plain_text(content))

    doc = Nokogiri::HTML::DocumentFragment.parse(clean)
    doc.traverse do |node|
      next unless node.text?
      next if node.ancestors.any? { |a| %w[a code pre].include?(a.name) }
      next unless node.text.match?(SOCIAL_TOKEN_REGEX)

      linked = safe_join(social_inline_nodes(node.text, users_by_username))
      node.replace(Nokogiri::HTML::DocumentFragment.parse(linked))
    end

    tag.div(doc.to_html.html_safe, class: [ "trix-content", class_name ].compact.join(" "), data: data)
  end

  def social_plain_text(content)
    text =
      if content.respond_to?(:to_plain_text)
        content.to_plain_text
      elsif content.is_a?(ActionText::Content)
        content.to_plain_text
      else
        content.to_s
      end

    CGI.unescapeHTML(text.to_s).gsub(/\r\n?/, "\n").strip
  end

  def social_mentioned_users(text)
    usernames = text.scan(/(?<![\w@])@([a-zA-Z0-9_]{3,30})/).flatten.map(&:downcase).uniq
    usernames -= %w[everyone all here]
    return {} if usernames.blank?

    User.where("LOWER(username) IN (?)", usernames).index_by { |user| user.username.downcase }
  end

  def social_inline_nodes(line, users_by_username)
    nodes = []
    cursor = 0

    line.to_enum(:scan, SOCIAL_TOKEN_REGEX).each do
      match = Regexp.last_match
      nodes << escape_social_text(line[cursor...match.begin(0)]) if match.begin(0) > cursor
      nodes.concat social_token_nodes(match[0], users_by_username)
      cursor = match.end(0)
    end

    nodes << escape_social_text(line[cursor..]) if cursor < line.length
    nodes
  end

  def social_inline_paragraph_nodes(paragraph, users_by_username)
    paragraph.split(/\n/, -1).each_with_index.flat_map do |line, index|
      nodes = social_inline_nodes(line, users_by_username)
      index.zero? ? nodes : [ tag.br, *nodes ]
    end
  end

  def social_token_nodes(token, users_by_username)
    if token.start_with?("@")
      [ social_mention_node(token, users_by_username) ]
    else
      social_url_nodes(token)
    end
  end

  def social_mention_node(token, users_by_username)
    handle = token.delete_prefix("@")

    case handle.downcase
    when "everyone"
      tag.span("@everyone", class: "mention-broadcast", data: { scope: "room" })
    when "all"
      tag.span("@all", class: "mention-broadcast mention-broadcast-platform", data: { scope: "platform" })
    else
      user = users_by_username[handle.downcase]
      return escape_social_text(token) unless user

      link_to("@#{user.username}", user_path(user.username), class: "mention-link")
    end
  end

  def social_url_nodes(token)
    url = token.dup
    trailing = +""

    while url.match?(/[),.!?:;]\z/)
      trailing.prepend(url.slice!(-1))
    end

    [
      link_to(url, url, class: "fc-social-link", target: "_blank", rel: "noopener noreferrer"),
      escape_social_text(trailing)
    ]
  end

  def escape_social_text(text)
    ERB::Util.html_escape(text.to_s)
  end
end
