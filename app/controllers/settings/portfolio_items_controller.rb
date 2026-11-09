# frozen_string_literal: true

module Settings
  # Adding, editing, ordering and removing pieces of work.
  class PortfolioItemsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_item, only: %i[edit update destroy move]

    def index
      @items = current_user.portfolio_items.with_attached_images
    end

    def new
      @item = current_user.portfolio_items.new
    end

    def create
      @item = current_user.portfolio_items.new(item_params)
      if @item.save
        redirect_to portfolio_work_path(current_user.username, @item), notice: "Added to your portfolio."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      attrs = item_params
      # New photos are added to the ones kept (like editing a breath), so the
      # count and type checks still run on the whole set.
      added = Array(attrs.delete(:images)).compact_blank
      removed = Array(params.dig(:portfolio_item, :remove_image_ids)).map(&:to_i)
      if added.any? || removed.any?
        kept = @item.images.attachments.reject { |a| removed.include?(a.id) }.map { |a| a.blob.signed_id }
        attrs[:images] = kept + added
      end
      drop_document = params.dig(:portfolio_item, :remove_document) == "1" && attrs[:document].blank?

      if @item.update(attrs)
        @item.document.purge_later if drop_document
        redirect_to portfolio_work_path(current_user.username, @item), notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @item.destroy
      redirect_to settings_portfolio_items_path, notice: "Removed from your portfolio.", status: :see_other
    end

    def move
      @item.move!(params[:direction])
      redirect_to settings_portfolio_items_path, status: :see_other
    end

    private

    def set_item
      @item = current_user.portfolio_items.find(params[:id])
    end

    def item_params
      params.require(:portfolio_item).permit(:title, :summary, :description, :category, :contribution, :link_url, :skills_list,
                                             :completed_month, :document, images: [])
    end
  end
end
