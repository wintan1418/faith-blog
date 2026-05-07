# frozen_string_literal: true

class DraftsController < ApplicationController
  before_action :authenticate_user!

  def index
    @pagy, @drafts = pagy(current_user.posts.where(status: :draft).order(updated_at: :desc), items: 30)
  end
end
