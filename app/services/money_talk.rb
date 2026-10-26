# frozen_string_literal: true

# Spots money talk in a chat message so the person receiving it sees a short
# safety tip. Nothing is blocked here: brethren help each other and do honest
# business. Clear scams are removed by the AI check (MessageModerationJob).
module MoneyTalk
  PATTERNS = [
    /\b(?:account|acct|acc)\s*(?:no|num|number|details)\b/i,
    /\b(?:bank|transfer|send\s+(?:me\s+)?money|pay\s+(?:me|into|to)|payment|deposit|loan|invest(?:ment)?|profit|returns?)\b/i,
    /\b(?:naira|ngn|usd|dollars?|pounds?|cedis?|usdt|crypto|bitcoin|btc|forex|gift\s*card)\b/i,
    /\b(?:opay|palmpay|moniepoint|kuda|paypal|cash\s*app|western\s+union|moneygram)\b/i,
    /\b(?:otp|pin|bvn|cvv|password|card\s+(?:number|details))\b/i,
    /[₦$£€]\s*\d|\b\d+(?:[.,]\d+)?\s*(?:k|m)\b/i
  ].freeze

  module_function

  def mentions?(text)
    text.present? && PATTERNS.any? { |pattern| text.match?(pattern) }
  end
end
