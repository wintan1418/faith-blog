# frozen_string_literal: true

# The Daily Breath prompt — one rotating question a day that invites the
# community to write, not just read. Deterministic per calendar day so
# everyone sees the same prompt and the feed fills with answers to it.
module DailyPrompt
  PROMPTS = [
    "What's one mercy you noticed yesterday?",
    "Which verse carried you this week — and why?",
    "What are you trusting God for right now?",
    "Describe a moment you felt God's presence recently.",
    "What's a prayer you've been praying for a long time?",
    "Who showed you Christ's love this week?",
    "What's one thing you're grateful for this morning?",
    "What truth are you preaching to yourself today?",
    "Where do you need courage right now?",
    "What has God been teaching you lately?",
    "Share a lyric or hymn line that's been on your heart.",
    "What would you tell your younger self about faith?",
    "What's a small obedience you're working on?",
    "How did you see prayer answered this month?",
    "What burden can the brethren help you carry today?",
    "What does rest in God look like for you this season?",
    "Which Bible character do you relate to right now — and why?",
    "What's one habit that's been feeding your soul?",
    "Where have you seen God's faithfulness in your family?",
    "What are you learning about forgiveness?",
    "What's a question about faith you're sitting with?",
    "Share a word of encouragement for someone starting their week.",
    "What did you hear in church or fellowship that stuck with you?",
    "What's one way you want to love your neighbour better?",
    "What fear are you handing over to God today?",
    "Describe a place where you feel closest to God.",
    "What scripture do you return to when life is heavy?",
    "What's a testimony you've never shared here?",
    "How has your prayer life changed over the years?",
    "What does 'walking by faith' mean to you this week?",
    "Who are you praying for today? (No names needed.)",
    "What's one promise of God you're standing on?",
    "What made you smile this week that felt like grace?",
    "What's something you're waiting on God for?",
    "How do you fight discouragement?",
    "What would you thank God for if today were your last day?",
    "What's one lesson a hard season taught you?",
    "Which fruit of the Spirit is God growing in you right now?",
    "What's your earliest memory of faith?",
    "Write a one-sentence prayer for the community."
  ].freeze

  # Same prompt for everyone all day; rotates through the whole list
  # before repeating.
  def self.today(date = Date.current)
    PROMPTS[(date.jd) % PROMPTS.size]
  end
end
