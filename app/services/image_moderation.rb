# frozen_string_literal: true

require "net/http"

# Shows uploaded pictures to the AI moderator (shrunk first, so it's quick and cheap).
module ImageModeration
  MAX_IMAGES = 4
  MAX_BYTES = 5.megabytes
  VISION_TYPES = %w[image/jpeg image/png image/webp image/gif image/heic image/heif].freeze

  module_function

  # Ai::Moderation::Result for the pictures, or nil when there's nothing to check.
  def review(attachments, kind:, context: nil)
    list = Array(attachments).first(MAX_IMAGES)
    images = list.filter_map { |attachment| payload(attachment) }
    return nil if images.empty?

    names = list.map { |a| a.try(:filename).to_s }.compact_blank.join(", ")
    Ai::Moderation::Reviewer.call(content: [ "Image files: #{names}", context ].compact_blank.join("\n"),
                                  kind: "#{kind} image", images: images)
  end

  def payload(attachment)
    blob = attachment.try(:blob) || attachment
    return unless blob.is_a?(ActiveStorage::Blob) && blob.image?

    if blob.service.class.name == "ActiveStorage::Service::CloudinaryService"
      url = blob.service.url(blob.key, filename: blob.filename, content_type: blob.content_type,
                             transformation: [ { width: 768, height: 768, crop: "limit", quality: "auto", fetch_format: "jpg" } ])
      { mime: "image/jpeg", data: Base64.strict_encode64(fetch(url)) }
    elsif VISION_TYPES.include?(blob.content_type) && blob.byte_size <= MAX_BYTES
      { mime: blob.content_type, data: Base64.strict_encode64(blob.download) }
    end
  rescue StandardError => e
    Rails.logger.warn("[ImageModeration] couldn't read image #{blob&.id}: #{e.class}: #{e.message}")
    nil
  end

  def fetch(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 6, read_timeout: 10) do |http|
      response = http.get(uri.request_uri)
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end

  # Worse of two results (nil-safe), by severity then action.
  def worse(first, second)
    return first || second if first.nil? || second.nil?

    rank = ->(r) { [ Ai::Moderation::Policy::SEVERITIES.index(r.severity).to_i, Ai::Moderation::Policy::ACTIONS.index(r.recommended_action).to_i ] }
    (rank.call(second) <=> rank.call(first)).positive? ? second : first
  end
end
