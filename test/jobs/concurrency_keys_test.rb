require "test_helper"

# Solid Queue calls each job's concurrency key with every argument the job was
# enqueued with. A key that accepted fewer arguments raised ArgumentError at
# enqueue time, which crashed every post edit (recheck: true) in production.
class ConcurrencyKeysTest < ActiveSupport::TestCase
  test "AI moderation gate key accepts a plain post id and an edit recheck" do
    assert_equal 42, AiModerationGateJob.new(42).concurrency_key.to_s.split("/").last.to_i
    assert_nothing_raised { AiModerationGateJob.new(42, recheck: true).concurrency_key }
  end

  test "office reply key accepts its argument" do
    assert_nothing_raised { OfficeReplyJob.new(7).concurrency_key }
  end

  test "bible reminder key accepts no arguments and a time" do
    assert_nothing_raised { BibleReminderJob.new.concurrency_key }
    assert_nothing_raised { BibleReminderJob.new(Time.current).concurrency_key }
  end
end
