# frozen_string_literal: true

# The Wall of Answered Prayers: every prayer request the community carried
# that was marked answered, newest answer first. Public — testimony is for
# everyone, signed in or not.
class AnsweredPrayersController < ApplicationController
  def index
    scope = Post.published
                .answered_prayers
                .where.not(prayer_answered_at: nil)
                .includes(:user, :room, :rich_text_content)
                .order(prayer_answered_at: :desc)

    @total_answered   = scope.count
    @total_interceded = scope.sum(:intercessions_count)
    @pagy, @posts     = pagy(scope, items: 18)
  end
end
