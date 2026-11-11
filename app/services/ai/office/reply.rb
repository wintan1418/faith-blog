# frozen_string_literal: true

module Ai
  module Office
    # What a provider hands back for one model turn, whatever the provider.
    #   tool_calls: [{ "id" => "...", "name" => "draft_breath", "input" => {...} }]
    #   raw:        the provider's own content, replayed as-is on the next turn
    Reply = Data.define(:text, :tool_calls, :model, :raw, :stop_reason) do
      def initialize(text: "", tool_calls: [], model: nil, raw: nil, stop_reason: nil)
        super
      end

      def tool_calls? = tool_calls.any?
    end
  end
end
