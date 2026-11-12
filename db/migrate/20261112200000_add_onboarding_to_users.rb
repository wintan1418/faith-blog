# frozen_string_literal: true

# First-run onboarding on the feed: the getting-started checklist (hidden for
# now, or finished for good) and the one-time tooltip tour.
class AddOnboardingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :onboarding_dismissed_at, :datetime
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :tour_completed_at, :datetime
  end
end
