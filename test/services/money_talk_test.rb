# frozen_string_literal: true

require "test_helper"

class MoneyTalkTest < ActiveSupport::TestCase
  test "spots money talk" do
    [ "send me your account number", "I'll transfer it tonight", "how much? 5k?", "₦20,000 only",
      "pay into my opay", "what is your OTP", "invest in forex with me" ].each do |text|
      assert MoneyTalk.mentions?(text), "should spot: #{text}"
    end
  end

  test "ignores ordinary chat" do
    [ "God bless you sister", "see you at service on Sunday", "pray for my exams", "", nil ].each do |text|
      assert_not MoneyTalk.mentions?(text), "should ignore: #{text.inspect}"
    end
  end
end
