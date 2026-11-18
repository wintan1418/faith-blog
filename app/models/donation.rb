# frozen_string_literal: true

# A gift to Brethreign, paid through Paystack (see GivingController).
class Donation < ApplicationRecord
  CURRENCIES = {
    "NGN" => { symbol: "₦", presets: [ 2_000, 5_000, 10_000, 25_000 ], min: 500 },
    "USD" => { symbol: "$", presets: [ 5, 10, 25, 50 ], min: 2 }
  }.freeze
  FREQUENCIES = %w[one_time monthly].freeze
  STATUSES = %w[pending paid failed].freeze

  belongs_to :user, optional: true

  validates :currency, inclusion: { in: CURRENCIES.keys }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :status, inclusion: { in: STATUSES }
  validates :reference, presence: true, uniqueness: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, length: { maximum: 500 }
  validate :amount_at_least_minimum

  before_validation { self.reference ||= "BR-#{SecureRandom.hex(8).upcase}" }

  scope :paid, -> { where(status: "paid") }

  # Whether visitors (not just admins) can see the giving page.
  def self.public? = ENV["DONATIONS_PUBLIC"] == "1"

  # Payments work once the business account's Paystack key is set.
  def self.payments_open? = Paystack.configured?

  def amount = amount_minor && amount_minor / 100.0

  def amount=(value)
    self.amount_minor = value.present? ? (value.to_s.to_d * 100).round : nil
  end

  def monthly? = frequency == "monthly"
  def paid? = status == "paid"

  def display_amount
    "#{CURRENCIES.dig(currency, :symbol)}#{ActiveSupport::NumberHelper.number_to_delimited(amount % 1 == 0 ? amount.to_i : amount)}"
  end

  # Marks it paid once (the redirect back and the webhook may both arrive).
  def mark_paid!
    with_lock { update!(status: "paid", paid_at: Time.current) unless paid? }
  end

  private

  def amount_at_least_minimum
    min = CURRENCIES.dig(currency, :min)
    return if min.nil? || amount_minor.to_i >= min * 100
    errors.add(:amount, "must be at least #{CURRENCIES.dig(currency, :symbol)}#{min}")
  end
end
