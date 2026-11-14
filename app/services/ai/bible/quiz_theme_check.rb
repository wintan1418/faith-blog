# frozen_string_literal: true

module Ai
  module Bible
    # Asks the AI which of a theme's pool questions are NOT about that theme.
    # Questions written before QuizGenerator::THEME_BOOKS could drift off theme
    # (the book hint was any NT book), so `bin/rails bible_quiz:audit_themes`
    # uses this to take those out of the quiz. Returns the off-theme ids.
    class QuizThemeCheck
      TASK_MARKER = "[TASK:BIBLE_QUIZ_THEME_CHECK]"
      BATCH = 20

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You check Bible quiz questions against the THEME a player picked.
        A question is on theme only if it is clearly ABOUT that theme (its
        subject, the verse it quotes, or the answer). A question that merely
        quotes some verse, or is about a different topic, is off theme.
        When unsure, count it as on theme.

        Return ONLY a JSON object, no prose, no markdown fences:
        { "off_theme_ids": [ids of the questions that are off theme] }
      PROMPT

      def self.call(theme:, questions:)
        new(theme: theme, questions: questions).call
      end

      def initialize(theme:, questions:)
        @theme = theme.to_s
        @questions = Array(questions).first(BATCH)
      end

      def call
        return [] if @questions.empty? || !QuizGenerator::THEMES.key?(@theme)

        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        ids = Array(JSON.parse(text)["off_theme_ids"]).map(&:to_i)
        ids & @questions.map(&:id) # only ids we asked about
      rescue JSON::ParserError
        []
      end

      private

      def user_prompt
        lines = @questions.map do |q|
          { id: q.id, prompt: q.prompt, answer: Array(q.choices)[q.correct_index.to_i], reference: q.reference }.to_json
        end
        <<~PROMPT
          #{TASK_MARKER}
          THEME: #{@theme} — #{QuizGenerator::THEMES[@theme]}

          QUESTIONS (one JSON object per line):
          #{lines.join("\n")}
        PROMPT
      end
    end
  end
end
