# frozen_string_literal: true

class PrayerIntercession < ApplicationRecord
  belongs_to :user
  belongs_to :post, counter_cache: :intercessions_count

  validates :user_id, uniqueness: { scope: :post_id, message: "is already in this prayer chain" }

  after_create_commit -> { Seeds.intercession_created(self) }
  # Leaving the chain takes the seeds back; a deleted prayer leaves them be.
  after_destroy_commit -> { Seeds.revoke_source(self) unless destroyed_by_association }
end
