# frozen_string_literal: true

# Chat message text with its web addresses made tappable. The text is escaped
# first, so only the links we add are markup. Brethreign links stay in the app
# (and in the native apps' own navigation); other sites open in a new tab.
module ChatTextHelper
  # An http(s) address in already-escaped text: stops at spaces, "<" and the
  # escaped quote and angle-bracket entities.
  CHAT_URL = %r{\bhttps?://(?:(?!&quot;|&#39;|&lt;|&gt;)[^\s<])+}i
  # Sentence punctuation after a link isn't part of it.
  CHAT_URL_TRAILING = /[.,!?;:)\]]+\z/
  INTERNAL_HOSTS = %w[brethreign.com].freeze

  def chat_text(text)
    linked = ERB::Util.html_escape(text.to_s).to_str.gsub(CHAT_URL) do |url|
      trailing = url[CHAT_URL_TRAILING].to_s
      url = url.delete_suffix(trailing)
      attrs = chat_link_internal?(url) ? %( data-turbo-frame="_top") : %( target="_blank" rel="noopener noreferrer nofollow ugc")
      %(<a href="#{url}" class="msg-link"#{attrs}>#{url}</a>#{trailing})
    end
    simple_format(linked.html_safe, {}, sanitize: false) # rubocop:disable Rails/OutputSafety -- escaped above; only our <a> tags are markup
  end

  private

  def chat_link_internal?(escaped_url)
    host = URI.parse(CGI.unescapeHTML(escaped_url)).host.to_s.downcase.delete_prefix("www.")
    INTERNAL_HOSTS.include?(host) || host == request&.host
  rescue URI::InvalidURIError
    false
  end
end
