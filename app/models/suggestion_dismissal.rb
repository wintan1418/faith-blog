# frozen_string_literal: true

# "Not interested" on a Brethren-you-may-know card.
class SuggestionDismissal < ApplicationRecord
  belongs_to :user
  belongs_to :dismissed_user, class_name: "User"
end
