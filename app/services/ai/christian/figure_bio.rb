# frozen_string_literal: true

module Ai
  module Christian
    # Generate a rich, warm 3–4-paragraph bio of a church-history figure.
    # The result is cached on the ChurchHistoryFigure row so each figure is
    # only ever generated once. Pulls from the model's structured fields
    # (name, era, dates, claim) for accuracy guard-rails.
    class FigureBio
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:CHURCH_HISTORY_BIO]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You write engaging short biographies of historical Christian figures
        for a Christian community app. Warm, factual, story-shaped. No
        sectarian polemics, no exaggeration of miracles.

        Given a figure's name, era, dates, and a one-line claim to fame,
        write a 3-paragraph biography (~220 words total):

          Paragraph 1 — origin and the moment of calling.
          Paragraph 2 — their life's work and its impact.
          Paragraph 3 — how they're remembered today; one famous quote
                        attributed to them if it's well-attested.

        Stay factual. If you're not sure about a detail, omit it rather
        than invent. Don't include verse numbers unless they're part of a
        widely-known quotation.

        Return ONLY a single JSON object, no prose, no markdown fences:
        { "bio": "<paragraph 1>\\n\\n<paragraph 2>\\n\\n<paragraph 3>",
          "quote": "<one famous quote with no attribution suffix>" }
      PROMPT

      def self.call(figure:)
        new(figure: figure).call
      end

      def initialize(figure:)
        @figure = figure
      end

      def call
        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)
        { bio: payload["bio"].to_s.strip, quote: payload["quote"].to_s.strip }
      end

      private

      def user_prompt
        <<~PROMPT
          #{TASK_MARKER}
          Name: #{@figure.name}
          Era: #{ChurchHistoryFigure::ERA_LABELS[@figure.era]}
          Dates: #{@figure.years}
          One-line claim: #{@figure.claim}
        PROMPT
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse bio response: #{e.message} — body: #{text}"
      end
    end
  end
end
