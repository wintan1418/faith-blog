# frozen_string_literal: true

# Times and labels for the inbox, LinkedIn-style.
module MessagingHelper
  # Conversation list: "3:41 PM" today, "Mon" this week, "Oct 12" this year, then "Oct 12, 2025".
  def inbox_time(time)
    time = time.in_time_zone
    now = Time.zone.now
    if time.to_date == now.to_date then time.strftime("%-l:%M %p")
    elsif time > 6.days.ago.beginning_of_day then time.strftime("%a")
    elsif time.year == now.year then time.strftime("%b %-d")
    else time.strftime("%b %-d, %Y")
    end
  end

  # Divider between days in a thread: "Today", "Yesterday", "Monday", "October 12", "October 12, 2025".
  def message_day_label(time)
    date = time.in_time_zone.to_date
    today = Time.zone.today
    if date == today then "Today"
    elsif date == today - 1 then "Yesterday"
    elsif date > today - 7 then date.strftime("%A")
    elsif date.year == today.year then date.strftime("%B %-d")
    else date.strftime("%B %-d, %Y")
    end
  end

  # A <time> the browser rewrites into the reader's own time zone (server text is the fallback).
  def local_time_tag(time, format, fallback)
    tag.time(fallback, datetime: time.utc.iso8601, data: { controller: "local-time", local_time_format_value: format })
  end

  # Consecutive messages from the same person within this gap share one name/photo header.
  MESSAGE_GROUP_GAP = 5.minutes

  def message_starts_group?(message, previous)
    return true if previous.nil?
    return true if previous.created_at.to_date != message.created_at.to_date

    previous.sender_id != message.sender_id || (message.created_at - previous.created_at) > MESSAGE_GROUP_GAP
  end

  def message_starts_day?(message, previous)
    previous.nil? || previous.created_at.in_time_zone.to_date != message.created_at.in_time_zone.to_date
  end

  # "You: …" for your own last message; a label for media-only messages.
  # "PDF · 2.4 MB" under a document's name in a chat.
  def document_meta(attachment)
    ext = File.extname(attachment.filename.to_s).delete(".").upcase.presence || "File"
    "#{ext} · #{number_to_human_size(attachment.byte_size)}"
  end

  # The coloured tile behind a document's file icon: "pdf", "doc", "sheet", "slides", "book" or "file".
  def document_kind(attachment)
    case File.extname(attachment.filename.to_s).downcase
    when ".pdf" then "pdf"
    when ".doc", ".docx", ".odt", ".rtf" then "doc"
    when ".xls", ".xlsx", ".ods", ".csv" then "sheet"
    when ".ppt", ".pptx", ".odp" then "slides"
    when ".epub" then "book"
    else "file"
    end
  end

  # Icon shown before an inbox row's preview for media-only messages (nil for text).
  def conversation_preview_icon(message)
    return unless message
    return if message.respond_to?(:removed?) && message.removed?
    return if message.body.present?

    if message.respond_to?(:has_voice_note?) && message.has_voice_note? then "mic"
    elsif message.respond_to?(:has_images?) && message.has_images? then "image"
    elsif message.respond_to?(:has_documents?) && message.has_documents? then "file"
    elsif message.respond_to?(:has_scripture?) && message.has_scripture? then "bookopen"
    end
  end

  # Bar heights (px) for a voice note's waveform-style progress bar. It is a
  # pattern, not the recording's real loudness: varied per message so notes
  # don't all look identical, and the same every time the message is drawn.
  VOICE_BARS = 28

  def voice_wave_bars(message)
    seed = message.id.to_i
    Array.new(VOICE_BARS) do |i|
      wobble = Math.sin((i + 1) * 0.9 + seed) * 0.5 + Math.sin((i + 1) * 0.37 + seed * 1.7) * 0.5
      (6 + ((wobble + 1) / 2.0) * 18).round
    end
  end

  def conversation_preview(message, viewer)
    return "No messages yet" unless message

    text =
      if message.respond_to?(:removed?) && message.removed? then "Message removed"
      elsif message.body.present? then message.body.squish
      elsif message.respond_to?(:has_voice_note?) && message.has_voice_note? then "Sent a voice note"
      elsif message.respond_to?(:has_images?) && message.has_images? then "Sent a photo"
      elsif message.respond_to?(:has_documents?) && message.has_documents? then "Sent a document"
      elsif message.respond_to?(:has_scripture?) && message.has_scripture? then "Shared a verse"
      else "Sent a message"
      end
    prefix = message.sender_id == viewer.id ? "You: " : ""
    "#{prefix}#{text}"
  end

  # Download link for a file in a chat: served from our own site, under the
  # file's original name, to the people in that conversation only.
  def message_file_download_path(message, attachment)
    conversation_message_file_path(message.conversation_id, message, attachment.id, filename: attachment.filename.to_s)
  end
end
