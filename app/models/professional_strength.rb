# frozen_string_literal: true

# How complete a member's professional profile is, worked out from what they've
# filled in (nothing is stored). Drives the strength meter and the checklist
# of next steps the owner sees on the Professional tab.
class ProfessionalStrength
  Step = Struct.new(:key, :label, :done, :points, :action, :path, :hint, keyword_init: true)

  LEVELS = [ [ 90, "All-star" ], [ 70, "Strong" ], [ 40, "Good" ], [ 0, "Starting" ] ].freeze
  SKILLS_TARGET = 5
  ABOUT_MIN = 40

  include Rails.application.routes.url_helpers

  def initialize(user)
    @user = user
    @profile = user.profile
  end

  def steps
    @steps ||= [
      step(:photo, "Profile photo", @profile&.avatar&.attached?, 10, "Add", edit_settings_profile_path),
      step(:headline, "Headline", @profile&.headline.present?, 15, "Add", edit_settings_professional_path),
      step(:current_role, "Current role", @user.experiences.any?(&:current?), 20, "Add", new_settings_experience_path),
      step(:education, "Education", @user.educations.any?, 10, "Add", new_settings_education_path),
      skills_step,
      step(:about, "A few lines about you", @profile&.bio.to_s.strip.length.to_i >= ABOUT_MIN, 10, "Write", edit_settings_profile_path),
      step(:church, "Your church", @profile&.assembly.present?, 10, "Add", edit_settings_professional_path),
      step(:city, "Your city", @profile&.location.present?, 10, "Add", edit_settings_profile_path)
    ]
  end

  def score = steps.select(&:done).sum(&:points)
  def level = LEVELS.find { |min, _| score >= min }.last
  def complete? = steps.all?(&:done)
  def next_steps = steps.reject(&:done)
  def done_steps = steps.select(&:done)

  private

  def step(key, label, done, points, action, path, hint = nil)
    Step.new(key: key, label: label, done: !!done, points: points, action: action, path: path, hint: hint)
  end

  def skills_step
    count = @profile&.skills.to_a.size
    hint = count.positive? && count < SKILLS_TARGET ? "you have #{count}" : nil
    step(:skills, "#{SKILLS_TARGET} skills", count >= SKILLS_TARGET, 15, "Add", edit_settings_professional_path, hint)
  end
end
