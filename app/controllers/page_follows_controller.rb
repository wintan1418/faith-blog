# frozen_string_literal: true

# Follow / unfollow a page. A signed-out visitor is sent to sign up and comes
# back to the page.
class PageFollowsController < ApplicationController
  before_action :set_page

  def create
    unless user_signed_in?
      store_location_for(:user, org_page_path(@page))
      return redirect_to new_user_registration_path, notice: "Create your account to follow #{@page.name}."
    end
    return redirect_back_or_to(org_page_path(@page), alert: "This page isn't taking followers right now.") unless @page.active?

    current_user.page_follows.find_or_create_by!(page: @page)
    respond_with_button(notice: "Following #{@page.name}. Its posts will show in your Following feed.")
  rescue ActiveRecord::RecordNotUnique
    respond_with_button
  end

  def destroy
    return authenticate_user! unless user_signed_in?

    follow = current_user.page_follows.find_by(page: @page)
    follow&.destroy
    respond_with_button(notice: "You've stopped following #{@page.name}.")
  end

  private

  def set_page
    @page = Page.find_by_handle!(params[:handle])
    raise ActiveRecord::RecordNotFound unless @page.visible_to?(current_user)
  end

  def respond_with_button(notice: nil)
    @page.reload
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@page, :follow),
                                                  partial: "org_pages/follow_button",
                                                  locals: { page: @page, following: @page.followed_by?(current_user) })
      end
      format.html { redirect_back_or_to org_page_path(@page), notice: notice }
    end
  end
end
