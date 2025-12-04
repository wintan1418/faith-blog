# frozen_string_literal: true

class PostTag < ApplicationRecord
  # Associations
  belongs_to :post
  belongs_to :tag, counter_cache: :usage_count

  # Validations
  validates :post_id, uniqueness: { scope: :tag_id }
end

