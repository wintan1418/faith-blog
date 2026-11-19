# frozen_string_literal: true

class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true
  validate :endpoint_is_a_push_service

  # Browsers only ever hand out endpoints on these push services. Anything else
  # would make us POST to an address of the caller's choosing (SSRF).
  PUSH_HOSTS = [
    /\Afcm\.googleapis\.com\z/,
    /\Aandroid\.googleapis\.com\z/,
    /\A([a-z0-9-]+\.)*push\.services\.mozilla\.com\z/,
    /\Aweb\.push\.apple\.com\z/,
    /\A([a-z0-9-]+\.)*notify\.windows\.com\z/
  ].freeze

  def self.allowed_endpoint?(endpoint)
    uri = URI.parse(endpoint.to_s)
    uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && uri.host.present? &&
      PUSH_HOSTS.any? { |re| re.match?(uri.host.downcase) }
  rescue URI::InvalidURIError
    false
  end

  # Sends a push to this subscription. Quietly drops the row if the push
  # service tells us the endpoint is gone (browser uninstalled / changed).
  def deliver(title:, body:, url: nil, icon: nil, tag: nil)
    return false unless self.class.allowed_endpoint?(endpoint) # rows saved before the check

    payload = { title: title, body: body, url: url, icon: icon, tag: tag }.compact

    WebPush.payload_send(
      message: JSON.dump(payload),
      endpoint: endpoint,
      p256dh: p256dh_key,
      auth: auth_key,
      vapid: WebPushConfig.vapid_options,
      ttl: 24 * 3600
    )
    update_column(:last_pushed_at, Time.current)
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    destroy
    false
  rescue WebPush::Error => e
    Rails.logger.warn("[PushSubscription##{id}] #{e.class}: #{e.message}")
    false
  end

  private

  def endpoint_is_a_push_service
    errors.add(:endpoint, "isn't a browser push service") unless self.class.allowed_endpoint?(endpoint)
  end
end
