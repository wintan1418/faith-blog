# frozen_string_literal: true

module Ai
  module Bible
    # Natural-language Bible search. Given a query like
    #   "where Jonathan and David made a covenant"
    # returns up to 6 references that match, each with a short reason.
    #
    # Distinct from Ai::Composer::ScriptureSuggester (which suggests verses for
    # a *draft post*) — the prompt here is tuned for content discovery instead
    # of pastoral fit.
    class Searcher
      class ParseError < StandardError; end

      TASK_MARKER = "[TASK:BIBLE_SEARCH]"

      SYSTEM_PROMPT = <<~PROMPT.freeze
        #{TASK_MARKER}
        You help users find Bible passages by topic, story, character, or phrase.

        Given a plain-language query (e.g. "Jonathan and David's covenant",
        "Jesus calms the storm", "where Paul talks about love"), return UP TO
        6 specific Bible references that contain or describe what the user is
        looking for, ordered by best match first.

        Rules:
        - Use canonical 66-book Protestant references in KJV-friendly form:
          "1 Samuel 18:1-4", "Mark 4:35-41", "1 Corinthians 13".
        - Prefer specific verses or short spans (1-6 verses) over full
          chapters, unless the chapter as a whole is the answer.
        - Each reason is ONE plain sentence, max 140 chars, no preachiness.
        - If you genuinely can't find anything, return an empty list — never
          fabricate references that don't exist.

        Return ONLY a single JSON object, no prose, no markdown fences:
        {
          "verses": [
            { "reference": string, "reason": string }
          ]
        }
      PROMPT

      Hit = Struct.new(:reference, :reason, keyword_init: true)

      Result = Struct.new(:verses, keyword_init: true) do
        def empty?
          verses.empty?
        end
      end

      def self.call(query:)
        new(query: query).call
      end

      def initialize(query:)
        @query = query.to_s.strip
      end

      def call
        return Result.new(verses: []) if @query.blank?

        raw = Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: user_prompt)
        payload = extract_payload(raw)

        verses = Array(payload["verses"]).first(6).map do |v|
          ref = v["reference"].to_s.strip
          next if ref.blank?

          Hit.new(reference: ref, reason: v["reason"].to_s.strip)
        end.compact

        Result.new(verses: verses)
      end

      private

      def user_prompt
        "#{TASK_MARKER}\nQuery:\n---\n#{@query}\n---"
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse bible search response: #{e.message} — body: #{text}"
      end
    end
  end
end
