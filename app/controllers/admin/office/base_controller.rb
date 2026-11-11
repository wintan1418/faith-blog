# frozen_string_literal: true

# Shared by every Admin → Office controller: admins only, each admin sees
# only their own conversations.
class Admin::Office::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!
  layout "admin"
  helper :office

  private

  def conversations
    current_user.office_conversations
  end

  def sidebar_conversations
    conversations.recent.limit(60)
  end
  helper_method :sidebar_conversations
end
