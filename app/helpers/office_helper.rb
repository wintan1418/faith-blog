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

  TOOL_LABELS = {
    "site_stats" => "Checked the site numbers",
    "recent_activity" => "Looked at recent activity",
    "draft_breath" => "Drafted a breath",
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
