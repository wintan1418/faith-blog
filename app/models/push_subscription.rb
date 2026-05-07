# frozen_string_literal: true

class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true

  # Sends a push to this subscription. Quietly drops the row if the push
  # service tells us the endpoint is gone (browser uninstalled / changed).
  def deliver(title:, body:, url: nil, icon: nil, tag: nil)
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
end
