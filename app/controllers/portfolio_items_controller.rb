# frozen_string_literal: true

# A piece of work, on its own page: gallery, write-up, link, PDF.
class PortfolioItemsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    @user = User.active.find_by!(username: params[:username])
    @item = @user.portfolio_items.find(params[:id])
    owner = user_signed_in? && current_user == @user
    raise ActiveRecord::RecordNotFound if @item.hidden? && !owner && !current_user&.admin_or_moderator?
    raise ActiveRecord::RecordNotFound unless visible_profile?(owner)

    @owner = owner
    visible = @user.portfolio_items.visible.to_a
    i = visible.index(@item)
    @previous = i && i.positive? ? visible[i - 1] : nil
    @next = i ? visible[i + 1] : nil
  end

  private

  def visible_profile?(owner)
    return true if @user.profile&.public_profile? != false || owner

    user_signed_in? && current_user.admin_or_moderator?
  end
end
