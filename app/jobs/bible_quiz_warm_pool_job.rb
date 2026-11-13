# frozen_string_literal: true

# Recurring (config/recurring.yml): queue a top-up for every theme ×
# difficulty whose trusted pool is below BibleQuizQuestion::POOL_TARGET, so
# players are served instantly from the pool. Safe when the AI isn't
# configured — BibleQuizTopUpJob logs and skips.
class BibleQuizWarmPoolJob < ApplicationJob
  queue_as :default

  def perform
    return 0 if Ai::Moderation::Client.stub?

    self.class.short_filters.count do |theme, difficulty|
      BibleQuizTopUpJob.enqueue_once(theme: theme, difficulty: difficulty)
    end
  end

  # [[theme, difficulty], …] pairs below target.
  def self.short_filters(target = BibleQuizQuestion::POOL_TARGET)
    counts = BibleQuizQuestion.trusted.group(:theme, :difficulty).count
    Ai::Bible::QuizGenerator::THEMES.keys.product(Ai::Bible::QuizGenerator::DIFFICULTIES).select do |pair|
      counts.fetch(pair, 0) < target
    end
  end
end
