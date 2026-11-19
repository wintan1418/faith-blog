# frozen_string_literal: true

# Per-request state. `user` is the signed-in viewer (set in
# ApplicationController); Post's `viewer_like` association reads it so a page
# of cards can preload "my reaction" in one query.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
