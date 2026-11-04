# frozen_string_literal: true

# A feed one of the Updates bots reads (a news site's RSS, a job board's API).
class BotSource < ApplicationRecord
  FORMATS = %w[rss remotive himalayas].freeze

  has_many :bot_items, dependent: :destroy

  validates :name, :url, presence: true
  validates :url, uniqueness: true, format: { with: %r{\Ahttps://}i, message: "must start with https://" }
  validates :bot, inclusion: { in: ->(_) { Bots::Catalog.keys } }
  validates :format, inclusion: { in: FORMATS }

  scope :active, -> { where(active: true) }

  def bot_info = Bots::Catalog.fetch(bot)
end
