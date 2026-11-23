class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # In production Solid Queue builds each job's concurrency key when it is
  # enqueued; the test adapter never does, so a broken key only failed live
  # (it crashed every post edit in Nov 2026). Build it in tests too, so any
  # enqueue in any test catches a key that doesn't fit the job's arguments.
  if Rails.env.test?
    before_enqueue { concurrency_key if respond_to?(:concurrency_key) && concurrency_limited? }
  end
end
