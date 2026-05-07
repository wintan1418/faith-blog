# frozen_string_literal: true

# Centralizes Web Push (VAPID) credentials. Reads from env so the same
# code works in dev, test, and prod — keys live in .env / Kamal secrets,
# never in source.

module WebPushConfig
  module_function

  def public_key
    ENV["VAPID_PUBLIC_KEY"].to_s
  end

  def private_key
    ENV["VAPID_PRIVATE_KEY"].to_s
  end

  def subject
    ENV["VAPID_SUBJECT"].presence || "mailto:noreply@brethreign.com"
  end

  def configured?
    public_key.present? && private_key.present?
  end

  def vapid_options
    {
      public_key: public_key,
      private_key: private_key,
      subject: subject
    }
  end
end
