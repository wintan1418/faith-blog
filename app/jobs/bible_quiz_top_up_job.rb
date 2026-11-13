# frozen_string_literal: true

# Grows the Bible Quiz pool for one theme × difficulty in the background so
# players never wait on the AI. Enqueued by GamesController#quiz_generate
# when a filter runs thin, and by BibleQuizWarmPoolJob on a schedule.
class BibleQuizTopUpJob < ApplicationJob
  queue_as :default

  # Each generator call yields ~5 questions.
  DEFAULT_BATCHES = 4
  # Stampede guard: at most one enqueue per filter in this window.
  ENQUEUE_GUARD_TTL = 10.minutes

  # Enqueue unless a top-up for the same filter was enqueued recently.
  # Returns true when a job was enqueued.
  def self.enqueue_once(theme: nil, difficulty: nil, batches: DEFAULT_BATCHES)
    key = [ "bible-quiz-top-up", theme.presence || "any", difficulty.presence || "any" ].join(":")
    return false unless Rails.cache.write(key, true, expires_in: ENQUEUE_GUARD_TTL, unless_exist: true)

    perform_later(theme.presence, difficulty.presence, batches)
    true
  rescue StandardError => e
    Rails.logger.warn("[BibleQuizTopUpJob] enqueue failed: #{e.class}: #{e.message}")
    false
  end

  # Returns the number of questions inserted.
  def perform(theme = nil, difficulty = nil, batches = DEFAULT_BATCHES, target = BibleQuizQuestion::POOL_TARGET)
    if Ai::Moderation::Client.stub?
      Rails.logger.info("[BibleQuizTopUpJob] AI provider not configured (stub) — skipping #{theme || 'any'}/#{difficulty || 'any'}")
      return 0
    end

    inserted = 0
    batches.to_i.times do
      break if BibleQuizQuestion.pool_size(theme: theme, difficulty: difficulty) >= target && inserted.positive?

      begin
        generated = Ai::Bible::QuizGenerator.call(theme: theme, difficulty: difficulty)
        inserted += BibleQuizQuestion.import_from_generator!(generated)
      rescue Ai::Moderation::Client::ConfigError => e
        Rails.logger.warn("[BibleQuizTopUpJob] AI not configured: #{e.message}")
        break
      rescue StandardError => e
        Rails.logger.warn("[BibleQuizTopUpJob] #{theme || 'any'}/#{difficulty || 'any'}: #{e.class}: #{e.message}")
      end
    end
    inserted
  end
end
