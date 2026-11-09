# frozen_string_literal: true

# Roles saved before the match keys existed had none, so "same employer" and
# "same job" suggestions (and the LinkedIn import's duplicate check) missed them.
class BackfillExperienceMatchKeys < ActiveRecord::Migration[8.1]
  class Role < ActiveRecord::Base
    self.table_name = "experiences"
  end

  def up
    Role.where(title_key: nil).or(Role.where(organization_key: nil)).find_each do |role|
      role.update_columns(title_key: MatchKey.for(role.title), organization_key: MatchKey.for(role.organization))
    end
  end

  def down; end
end
