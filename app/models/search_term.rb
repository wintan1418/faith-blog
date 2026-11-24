# frozen_string_literal: true

# A word seen in public breaths (SearchTermsRefreshJob), for "Did you mean …?".
class SearchTerm < ApplicationRecord
  self.primary_key = "term"
end
