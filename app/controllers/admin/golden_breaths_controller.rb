# frozen_string_literal: true

class Admin::GoldenBreathsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_breath, only: [ :edit, :update, :destroy, :toggle ]

  def index
    @pagy, @breaths = pagy(GoldenBreath.ordered, items: 24)
  end

  def new
    @breath = GoldenBreath.new(active: true)
  end

  def create
    @breath = GoldenBreath.new(breath_params)
    if @breath.save
      redirect_to admin_golden_breaths_path, notice: "Golden breath added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @breath.update(breath_params)
      redirect_to admin_golden_breaths_path, notice: "Golden breath updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @breath.destroy
    redirect_to admin_golden_breaths_path, notice: "Golden breath removed."
  end

  def toggle
    @breath.update(active: !@breath.active)
    redirect_to admin_golden_breaths_path, notice: "Breath #{@breath.active? ? "activated" : "deactivated"}."
  end

  private

  def set_breath
    @breath = GoldenBreath.find(params[:id])
  end

  def breath_params
    params.require(:golden_breath).permit(:text, :author_name, :reference, :source_url, :active, :position)
  end
end
