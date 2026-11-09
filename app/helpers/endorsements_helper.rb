# frozen_string_literal: true

module EndorsementsHelper
  # This member's endorsements grouped by skill key, newest first (one query per page).
  def endorsements_by_skill(user)
    @endorsements_by_skill ||= {}
    @endorsements_by_skill[user.id] ||= user.skill_endorsements
                                            .includes(endorser: { profile: { avatar_attachment: :blob } })
                                            .order(created_at: :desc).group_by(&:skill_key)
  end

  def skill_row_id(user, skill)
    "skill_#{user.id}_#{Digest::MD5.hexdigest(SkillEndorsement.key_for(skill)).first(10)}"
  end
end
