# frozen_string_literal: true

# A page's team. Owners and admins invite people by username (they get an
# alert and accept it), change roles and remove people; only the owner can
# make or remove admins, and hand the page to someone else. Anyone can leave
# a team (except the owner, who hands it over first) or turn down an invite.
class PageMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_page
  before_action :set_membership, only: %i[update destroy accept]
  member_rate_limit to: 30, within: 1.hour, only: :create, name: "page-invite"

  def create
    return deny unless @page.manager?(current_user)

    username = params[:username].to_s.strip.delete_prefix("@")
    role = params[:role].presence_in(%w[admin editor]) || "editor"
    return back("Only the owner can add admins.", alert: true) if role == "admin" && !@page.owner?(current_user)

    user = User.active.find_by("lower(username) = ?", username.downcase)
    return back("We couldn't find @#{username}.", alert: true) if user.nil?
    return back("@#{user.username} is already on the team.", alert: true) if @page.memberships.exists?(user_id: user.id)
    return back("You can't add @#{user.username}.", alert: true) if MessageBlock.between?(current_user.id, user.id) || user.profile&.minor?

    membership = @page.memberships.create(user: user, role: role, status: :pending, invited_by: current_user)
    return back(membership.errors.full_messages.to_sentence, alert: true) unless membership.persisted?

    Notification.create(user: user, actor: current_user, notifiable: membership, notification_type: :page_invite)
    back("Invite sent to @#{user.username}. They'll join the team once they accept.")
  end

  # Change someone's role (admin <-> editor).
  def update
    return deny unless @page.owner?(current_user)
    return back("Use “Hand over the page” to change the owner.", alert: true) if @membership.owner?

    @membership.update!(role: params[:role].presence_in(%w[admin editor]) || @membership.role)
    back("@#{@membership.user.username} is now #{@membership.role == 'admin' ? 'an admin' : 'an editor'}.")
  end

  def accept
    return deny unless @membership.user_id == current_user.id && @membership.pending?

    @membership.accept!
    Notification.where(notifiable: @membership, user: current_user).update_all(read_at: Time.current)
    redirect_to org_page_path(@page), notice: "You're now #{@membership.role == 'admin' ? 'an admin' : 'an editor'} of #{@page.name}. You can post as the page from the composer."
  end

  # Remove someone, leave the team yourself, or turn an invite down.
  def destroy
    yourself = @membership.user_id == current_user.id
    return back("Hand the page to someone else before you leave it.", alert: true) if @membership.owner?
    allowed = yourself || @page.owner?(current_user) || (@page.manager?(current_user) && @membership.editor?)
    return deny unless allowed

    @membership.destroy!
    Notification.where(notifiable: @membership).delete_all
    if yourself
      redirect_to org_page_path(@page), notice: @membership.pending? ? "Invite declined." : "You've left #{@page.name}'s team."
    else
      back("@#{@membership.user.username} is no longer on the team.")
    end
  end

  # The owner hands the page to an active admin and becomes an admin.
  def transfer
    return deny unless @page.owner?(current_user)

    target = @page.active_memberships.where(role: :admin).joins(:user).find_by("lower(users.username) = ?", params[:username].to_s.delete_prefix("@").downcase)
    return back("Pick one of the page's admins (they need to have accepted their invite).", alert: true) unless target
    return back("They already own #{Page::MAX_OWNED} pages.", alert: true) if !target.user.admin_or_moderator? &&
                                                                                PageMembership.active.owner.where(user_id: target.user_id).count >= Page::MAX_OWNED

    PageMembership.transaction do
      @page.memberships.find_by!(user_id: current_user.id).update!(role: :admin)
      target.update!(role: :owner)
    end
    redirect_to manage_org_page_path(@page, tab: "team"), notice: "@#{target.user.username} now owns #{@page.name}. You're an admin."
  end

  private

  def set_page
    @page = Page.find_by_handle!(params[:handle])
  end

  def set_membership
    @membership = @page.memberships.find(params[:id])
  end

  def back(message, alert: false)
    redirect_to manage_org_page_path(@page, tab: "team"), (alert ? :alert : :notice) => message
  end

  def deny
    redirect_to org_page_path(@page), alert: "You can't do that on this page."
  end
end
