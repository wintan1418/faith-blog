# frozen_string_literal: true

class UserRiskProfile < ApplicationRecord
  belongs_to :user

  enum :risk_level, {
    clear:      0,
    watch:      1,
    restricted: 2,
    suspended:  3,
    banned:     4
  }

  scope :elevated, -> { where.not(risk_level: :clear) }

  def cleared?
    clear?
  end

  def at_least?(level)
    self.class.risk_levels[risk_level] >= self.class.risk_levels[level.to_s]
  end
end
