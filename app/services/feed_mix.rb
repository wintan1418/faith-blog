# frozen_string_literal: true

require "zlib"

# Orders feed entries so one busy author can't fill the screen.
#
# The feed is still newest-first, but:
#   - no more than MAX_RUN (2) cards in a row from the same author, and
#   - no more than MAX_IN_WINDOW (3) from one author in any WINDOW (10) cards,
# whenever someone else's post is available to go in between. Extra posts
# from a busy author are pushed further down, not dropped.
#
# A light shuffle (each entry's time moved back by up to JITTER, from a hash of
# the seed and the entry) breaks up batches posted minutes apart. The seed is
# the viewer + the day of the snapshot, so the order is the same on every page
# of one visit (no duplicates or gaps) and changes a little from day to day.
#
# Entries are hashes: { kind:, id:, at:, author_id: }. Entries newer than
# `fresh_after` (the viewer's last visit) are placed before older ones.
class FeedMix
  MAX_RUN       = 2
  WINDOW        = 10
  MAX_IN_WINDOW = 3
  JITTER        = 45.minutes.to_i

  def self.call(...) = new(...).call

  def initialize(entries, seed:, fresh_after: nil, keep_order: false)
    @entries = entries
    @seed = seed
    @fresh_after = fresh_after
    @keep_order = keep_order
  end

  def call
    mix(@keep_order ? @entries : shuffled)
  end

  private

  def shuffled
    @entries.sort_by do |e|
      fresh = @fresh_after && e[:at] > @fresh_after ? 0 : 1
      [ fresh, -(e[:at].to_i - jitter(e)), e[:kind].to_s, -e[:id] ]
    end
  end

  def jitter(entry)
    Zlib.crc32("#{@seed}:#{entry[:kind]}:#{entry[:id]}") % JITTER
  end

  # Greedy: take the first (newest) entry that keeps the rules; if none does,
  # the first that at least avoids a third in a row; else just the next one.
  def mix(ordered)
    remaining = ordered.dup
    out = []
    until remaining.empty?
      index = remaining.index { |e| run_ok?(out, e) && window_ok?(out, e) } ||
              remaining.index { |e| run_ok?(out, e) } ||
              0
      out << remaining.delete_at(index)
    end
    out
  end

  def author(entry)
    entry[:author_id] || "#{entry[:kind]}-#{entry[:id]}"
  end

  def run_ok?(out, entry)
    tail = out.last(MAX_RUN)
    tail.size < MAX_RUN || tail.any? { |e| author(e) != author(entry) }
  end

  def window_ok?(out, entry)
    out.last(WINDOW - 1).count { |e| author(e) == author(entry) } < MAX_IN_WINDOW
  end
end
