# frozen_string_literal: true

require "test_helper"

class CityChangeTest < ActiveSupport::TestCase
  test "the next change is allowed 30 days after the oldest of the last two counted ones" do
    user = create_member("counter")
    assert_nil CityChange.next_change_at(user.id)

    first = CityChange.create!(user: user, to_city: cities(:owo), counted: true, created_at: 20.days.ago)
    CityChange.create!(user: user, to_city: cities(:akure), counted: false, created_at: 10.days.ago)
    assert_nil CityChange.next_change_at(user.id), "uncounted changes don't use up the allowance"

    CityChange.create!(user: user, to_city: cities(:lagos), counted: true, created_at: 5.days.ago)
    assert_in_delta (first.created_at + 30.days).to_f, CityChange.next_change_at(user.id).to_f, 1

    first.update_columns(created_at: 31.days.ago)
    assert_nil CityChange.next_change_at(user.id)
  end
end
