# frozen_string_literal: true

module Ai
  module Moderation
    Result = Struct.new(
      :safe,
      :severity,
      :categories,
      :score,
      :summary,
      :recommended_action,
      :raw_response,
      :model,
      keyword_init: true
    ) do
      def to_h
        {
          safe: safe,
          severity: severity,
          categories: categories,
          score: score,
          summary: summary,
          recommended_action: recommended_action,
          raw_response: raw_response,
          model: model
        }
      end

      def flagged?
        !safe
      end
    end
  end
end
