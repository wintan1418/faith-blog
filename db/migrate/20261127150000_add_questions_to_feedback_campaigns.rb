# frozen_string_literal: true

# Longer surveys: a campaign can carry its own list of questions (one answer,
# several answers, a text box, and where the 0–10 / stars rating sits), and an
# answer keeps every reply keyed by question. Plus an "also email" switch.
class AddQuestionsToFeedbackCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :feedback_campaigns, :questions, :jsonb, default: [], null: false
    add_column :feedback_campaigns, :also_email, :boolean, default: false, null: false
    add_column :feedback_responses, :answers, :jsonb, default: {}, null: false
  end
end
