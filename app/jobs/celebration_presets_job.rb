# frozen_string_literal: true

# Once a month: add the built-in occasions for the coming 12 months as drafts
# (or live, when the admin turned on "auto-activate presets").
class CelebrationPresetsJob < ApplicationJob
  queue_as :bulk

  def perform
    Celebrations::Presets.seed!
  end
end
