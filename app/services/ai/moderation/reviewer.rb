# frozen_string_literal: true

module Ai
  module Moderation
    class Reviewer
      class ParseError < StandardError; end

      SYSTEM_PROMPT = <<~PROMPT.freeze
        You are a content safety classifier for Brethreign, a Christian faith community
        where people share testimonies, prayer requests, doubts, and spiritual conversation.

        Be conservative. Flag clear policy violations. Do NOT flag:
        - Honest doubt, lament, or expressions of pain.
        - Theological disagreement that stays respectful.
        - Vulnerable testimony about past struggles, including past mention of suicide,
          abuse, or addiction shared as part of recovery — these need pastoral care, not removal.

        DO flag:
        - Active threats of violence or harm.
        - Active suicidal ideation directed at self or others (not historical recovery testimony).
        - Sexual exploitation, hate, harassment, scams, doxxing, explicit adult content.
        - Spiritual manipulation, predatory miracle/seed-money fundraising, dangerous
          medical advice presented as spiritual instruction, fake testimonies, spam.

        This community takes a strong stand against three things. Flag them firmly
        (severity "high", recommended_action "block") when the content promotes,
        offers or solicits them:
        - Sexual or raunchy content: sexual descriptions, sexting, flirting for sex,
          requests for nude photos, hook-ups, porn links. Category "explicit_adult"
          (or "sexual_exploitation" if a minor or coercion is involved).
          This includes hidden or coded sexual talk: innuendo, double meanings,
          slang and pet names for body parts ("kitty", "cookie", "toto", "thing",
          "package", "melons"), words like wet, dripping, hard, horny, "come and sit
          on", "what are you wearing", "send pics", "let's link up tonight" said with
          sexual intent, and sexual emojis (🍆 🍑 💦 👅 😈) used suggestively.
          Judge the meaning, not just the words.
        - Occult practice: witchcraft, sorcery, juju, charms, native doctors, money
          rituals, spells, divination, séances, "spiritual power" for sale.
          Category "occult". A testimony of being DELIVERED from the occult, or
          teaching against it, is NOT a violation.
        - Fraud and scams: asking for money, bank details, card numbers, OTPs or
          passwords; investment, forex, crypto or "doubling" schemes; fake jobs,
          loans, visas or grants; romance scams; impersonating a pastor or ministry
          to collect money. Category "scam". Kind: message (a private chat) deserves
          extra care here, because scammers work one-to-one.

        Insults and name-calling aimed at a person ("you idiot", "you madman",
        "your head is not correct", "your mother", mocking someone's looks) are
        harassment: category "harassment", severity at least "medium".

        Return ONLY a single JSON object, no prose, no markdown fences. Schema:
        {
          "safe": boolean,
          "severity": "none" | "low" | "medium" | "high",
          "categories": [string],
          "score": number between 0 and 1,
          "summary": string (max 240 chars, factual, no judgment),
          "recommended_action": "allow" | "suggest_edit" | "require_review" | "hide_pending_review" | "block"
        }
      PROMPT

      # For pictures: the same JSON answer, judged on what the images show.
      IMAGE_PROMPT = <<~PROMPT.freeze
        You are an image safety classifier for Brethreign, a Christian faith community.
        Look at each image. Flag it firmly (severity "high", recommended_action "block") if it shows:
        - Nudity, sexual or raunchy content, lingerie/underwear posing, sexual gestures
          (category "explicit_adult"; "sexual_exploitation" if a minor may be involved).
        - Occult material: witchcraft or juju items, ritual setups, charms, occult symbols
          used for practice, "native doctor" adverts (category "occult"). Ordinary church
          imagery, crosses, Bibles and art are fine.
        - Fraud: images asking for money, bank or card details, payment QR codes from
          strangers, fake receipts, investment/forex/crypto adverts (category "scam").
        - Graphic violence or gore (category "violence"); hate symbols (category "hate").
        Normal photos (people, worship, food, nature, screenshots of scripture) are safe.
        Return ONLY one JSON object with the schema:
        {"safe": boolean, "severity": "none"|"low"|"medium"|"high", "categories": [string],
         "score": number 0-1, "summary": string (max 200 chars), "recommended_action":
         "allow"|"suggest_edit"|"require_review"|"hide_pending_review"|"block"}
      PROMPT

      def self.call(content:, kind: "post", author_context: nil, images: [])
        new(content: content, kind: kind, author_context: author_context, images: images).call
      end

      def initialize(content:, kind: "post", author_context: nil, images: [])
        @images = images
        @content = content.to_s
        @kind = kind
        @author_context = author_context
      end

      def call
        raw = Client.call(system: @images.any? ? IMAGE_PROMPT : SYSTEM_PROMPT, user: user_prompt, images: @images)
        payload = extract_payload(raw)
        safe = payload.fetch("safe", true)

        Result.new(
          safe: safe,
          severity: normalize_severity(payload["severity"]),
          categories: Array(payload["categories"]),
          score: payload.fetch("score", 0.0).to_f,
          summary: payload.fetch("summary", ""),
          recommended_action: normalize_action(payload["recommended_action"], safe: safe),
          raw_response: raw,
          model: raw["model"].to_s.presence || "unknown"
        )
      end

      private

      # Models drift from the schema ("None", "Review", "hold"…). Anything the
      # policy doesn't recognise must be coerced onto the allowlist here —
      # off-list values downstream fail AiModerationReview validations and
      # wedge the post in :pending_review with no review row for the admins.
      def normalize_severity(value)
        value = value.to_s.strip.downcase
        Policy::SEVERITIES.include?(value) ? value : "none"
      end

      def normalize_action(value, safe:)
        value = value.to_s.strip.downcase
        return value if Policy::ACTIONS.include?(value)

        safe ? "allow" : "require_review"
      end

      def user_prompt
        ctx = @author_context.present? ? "Author context: #{@author_context}\n\n" : ""
        "Kind: #{@kind}\n#{ctx}Content:\n---\n#{@content}\n---"
      end

      def extract_payload(raw)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
        # Strip optional code fences if a model decides to wrap the JSON anyway.
        text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ParseError, "could not parse AI response: #{e.message} — body: #{text}"
      end
    end
  end
end
