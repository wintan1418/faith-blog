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
  def conversation_preview(message, viewer)
    return "No messages yet" unless message

    text =
      if message.respond_to?(:removed?) && message.removed? then "Message removed"
      elsif message.body.present? then message.body.squish
      elsif message.respond_to?(:has_voice_note?) && message.has_voice_note? then "Sent a voice note"
      elsif message.respond_to?(:has_images?) && message.has_images? then "Sent a photo"
      elsif message.respond_to?(:has_scripture?) && message.has_scripture? then "Shared a verse"
      else "Sent a message"
      end
    prefix = message.sender_id == viewer.id ? "You: " : ""
    "#{prefix}#{text}"
  end
end
