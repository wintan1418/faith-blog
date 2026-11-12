# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module OfficeHelper
  MARKDOWN_TAGS = %w[p br strong em b i del a ul ol li h1 h2 h3 h4 blockquote code pre hr table thead tbody tr th td].freeze
  MARKDOWN_ATTRIBUTES = %w[href title].freeze

  # The assistant's Markdown as safe HTML.
  def office_markdown(text)
    html = Kramdown::Document.new(text.to_s, input: "GFM", hard_wrap: true, auto_ids: false, syntax_highlighter: nil).to_html
    sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end

  # The founder's own words: escaped, line breaks kept.
  def office_plain(text)
    safe_join(text.to_s.split("\n").map { |line| h(line) }, tag.br)
  end

  # A Copy button for the complete text. The text sits in a <template> next to
  # the button (not read from the rendered page), so long drafts copy whole.
  def office_copy_button(text, label: "Copy", class_name: "fc-btn")
    return if text.blank?

    tag.span(class: "office-copy") do
      tag.template(text.to_s, data: { office_copy_source: true }) +
        tag.button(label, type: "button", class: class_name, data: { action: "office#copy", label: label }, title: "Copy the full text")
    end
  end

  # Breath card text as the founder would paste it: title, blank line, body.
  def office_breath_text(card) = [ card["title"], card["body"] ].map { |t| t.to_s.strip }.compact_blank.join("\n\n")

  TOOL_LABELS = {
    "site_stats" => "Checked the site numbers",
    "recent_activity" => "Looked at recent activity",
    "draft_breath" => "Drafted a breath",
    "update_breath" => "Updated a breath",
    "generate_flyer" => "Made a flyer",
    "draft_email" => "Saved an email draft",
    "draft_announcement" => "Drafted an announcement"
  }.freeze

  def office_tool_label(name) = TOOL_LABELS.fetch(name.to_s, name.to_s.humanize)

  # Lagos time for a stored ISO time, e.g. "Thu 12 Nov, 08:00 WAT".
  def office_time(iso)
    return if iso.blank?

    Time.zone.parse(iso.to_s).in_time_zone(Ai::Office::BreathPublisher::TZ).strftime("%a %-d %b, %H:%M WAT")
  rescue ArgumentError
    nil
  end

  # "2026-11-12T08:00" for a datetime-local input, an hour from now by default.
  def office_datetime_value(iso)
    time = (Time.zone.parse(iso.to_s) if iso.present?) || 1.hour.from_now
    time.in_time_zone(Ai::Office::BreathPublisher::TZ).strftime("%Y-%m-%dT%H:%M")
  end
end
