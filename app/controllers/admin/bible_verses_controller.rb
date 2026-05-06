# frozen_string_literal: true

class Admin::BibleVersesController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_verse, only: [ :edit, :update, :destroy, :toggle ]

  def index
    @pagy, @verses = pagy(BibleVerse.ordered, items: 30)
  end

  def new
    @verse = BibleVerse.new(active: true)
  end

  def create
    @verse = BibleVerse.new(verse_params)
    if @verse.save
      ModerationLog.log_action(moderator: current_user, action: "verse_created", target: @verse) rescue nil
      redirect_to admin_bible_verses_path, notice: "Verse added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @verse.update(verse_params)
      redirect_to admin_bible_verses_path, notice: "Verse updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @verse.destroy
    redirect_to admin_bible_verses_path, notice: "Verse removed."
  end

  def toggle
    @verse.update(active: !@verse.active)
    redirect_to admin_bible_verses_path, notice: "Verse #{@verse.active? ? "activated" : "deactivated"}."
  end

  private

  def set_verse
    @verse = BibleVerse.find(params[:id])
  end

  def verse_params
    params.require(:bible_verse).permit(:text, :reference, :active, :position)
  end
end
