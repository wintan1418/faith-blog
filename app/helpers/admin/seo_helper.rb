# frozen_string_literal: true

# Formatting for Admin → Search & indexing.
module Admin::SeoHelper
  def seo_number(value)
    value.nil? ? "–" : number_with_delimiter(value.to_i)
  end

  def seo_ctr(value)
    value.nil? ? "–" : "#{number_with_precision(value.to_f * 100, precision: 1)}%"
  end

  def seo_position(value)
    value.nil? ? "–" : number_with_precision(value.to_f, precision: 1)
  end

  # "https://brethreign.com/posts/x" -> "/posts/x"
  def seo_path(url)
    uri = URI.parse(url.to_s)
    uri.host == SearchIndexing::HOST ? (uri.path.presence || "/") : url.to_s
  rescue URI::InvalidURIError
    url.to_s
  end

  def seo_time(value)
    time = value.is_a?(String) ? Time.zone.parse(value) : value
    return "–" unless time

    tag.time(time.strftime("%-d %b %Y, %H:%M"), datetime: time.iso8601, title: time.iso8601)
  rescue ArgumentError
    value.to_s
  end

  # Google's SCREAMING_CASE enum values in words ("SUBMITTED_AND_INDEXED" -> "Submitted and indexed").
  def seo_enum(value)
    return "Not reported" if value.blank?

    value.to_s.downcase.tr("_", " ").sub(/\A\w/, &:upcase)
  end

  def seo_verdict_class(verdict)
    case verdict.to_s
    when "PASS" then "badge badge-success"
    when "FAIL" then "badge badge-primary"
    else "badge"
    end
  end
end
