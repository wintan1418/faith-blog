# frozen_string_literal: true

class ChurchHistoryEra < ApplicationRecord
  validates :slug, presence: true, uniqueness: true
end
