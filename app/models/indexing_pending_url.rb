# frozen_string_literal: true

# A changed public URL waiting for the next IndexNow batch. Collecting them for
# a few minutes turns a burst of edits into one request.
class IndexingPendingUrl < ApplicationRecord
  validates :url, presence: true
end
