# frozen_string_literal: true

require "test_helper"

class BirthdayTest < ActiveSupport::TestCase
  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: generated_password)
  end

  def connect(a, b)
    ConnectionRequest.new(sender: a, receiver: b, status: :accepted).save!(validate: false)
  end

  setup do
    @today = Profile.today_for_birthdays
    @celebrant = make_user("celebrant")
    @friend = make_user("friend")
    @stranger = make_user("stranger")
    connect(@celebrant, @friend)
    @celebrant.profile.update!(birth_month: @today.month, birth_day: @today.day, birth_year: 1990)
  end

  test "connections see today's birthdays; strangers don't" do
    assert_equal [ @celebrant ], @friend.brethren_birthdays_today.to_a
    assert_empty @stranger.brethren_birthdays_today
  end

  test "people who hide their birthday aren't shown" do
    @celebrant.profile.update!(show_birthday: false)
    assert_empty @friend.brethren_birthdays_today
  end

  test "the morning job notifies connections once" do
    2.times { BirthdayNotificationsJob.perform_now(@today) }

    assert_equal 1, @friend.notifications.birthday.count
    assert_equal 0, @stranger.notifications.birthday.count
    assert_match "celebrant's birthday", @friend.notifications.birthday.sole.message
  end

  test "Feb 29 birthdays are celebrated on Feb 28 in other years" do
    @celebrant.profile.update!(birth_month: 2, birth_day: 29)

    assert_includes Profile.birthday_on(Date.new(2027, 2, 28)), @celebrant.profile
    assert_not_includes Profile.birthday_on(Date.new(2028, 2, 28)), @celebrant.profile
    assert_includes Profile.birthday_on(Date.new(2028, 2, 29)), @celebrant.profile
  end

  test "birthdays must be real dates" do
    assert_not @celebrant.profile.update(birth_month: 2, birth_day: 31)
    assert_not @celebrant.profile.update(birth_month: 4, birth_day: nil)
    assert_equal "February 29", Profile.new(birth_month: 2, birth_day: 29).birthday_label
  end
end
