# frozen_string_literal: true

# "+ Endorse" on someone's skill (connections only). Answers with the
# updated skill row, so the button flips in place.
class EndorsementsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_member

  def create
    endorsement = current_user.given_endorsements.new(user: @member, skill: params[:skill].to_s)
    flash.now[:alert] = endorsement.errors.full_messages.to_sentence unless endorsement.save
    respond(endorsement.skill.presence || params[:skill].to_s)
  end

  def destroy
    key = SkillEndorsement.key_for(params[:skill])
    current_user.given_endorsements.where(user: @member, skill_key: key).destroy_all
    respond(@member.profile&.skills.to_a.find { |s| SkillEndorsement.key_for(s) == key } || params[:skill].to_s)
  end

  private

  def set_member
    @member = User.active.find_by!(username: params[:username])
  end

  def respond(skill)
    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.replace(helpers.skill_row_id(@member, skill), partial: "users/skill_row",
                                                                           locals: { user: @member, skill: skill, owner: false }) ]
        streams << turbo_stream.replace("flash_messages", partial: "shared/flash") if flash.now[:alert]
        render turbo_stream: streams
      end
      format.html { redirect_to user_path(@member.username, tab: "professional"), alert: flash.now[:alert] }
    end
  end
end
