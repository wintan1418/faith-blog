# frozen_string_literal: true

# "How to earn seeds", and remembering that a rank-up celebration was seen.
class SeedsController < ApplicationController
  before_action :authenticate_user!, only: :rank_seen

  def show
    @rules = Seeds::RULES
    @ranks = Seeds::Rank.all
  end

  def rank_seen
    reached = current_user.seeds_rank_reached.to_i
    current_user.update_column(:seeds_rank_seen, reached) if current_user.seeds_rank_seen.to_i < reached
    head :no_content
  end
end
