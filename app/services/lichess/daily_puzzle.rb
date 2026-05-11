# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Lichess
  # Fetches today's daily puzzle from Lichess. Free, no auth required.
  # Cached for an hour so we don't hammer their API.
  class DailyPuzzle
    ENDPOINT  = "https://lichess.org/api/puzzle/daily"
    CACHE_TTL = 1.hour

    def self.fetch
      cached = Rails.cache.read("lichess:daily_puzzle") rescue nil
      return cached if cached

      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 4
      http.read_timeout = 5

      response = http.request(Net::HTTP::Get.new(uri))
      return nil unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      puzzle  = payload.dig("puzzle") || {}
      game    = payload.dig("game") || {}
      # Find the FEN at the puzzle's initial ply. Lichess returns PGN of the
      # game plus the ply where the puzzle starts; the responsibility for
      # turning that into a FEN is in fen_from_game (heuristic, falls back
      # to the starting FEN if anything goes wrong).
      fen     = fen_from_game(game, puzzle["initialPly"])
      data    = {
        id:       puzzle["id"],
        rating:   puzzle["rating"].to_i,
        plays:    puzzle["plays"].to_i,
        themes:   Array(puzzle["themes"]),
        solution: Array(puzzle["solution"]),
        fen:      fen,
        link:     "https://lichess.org/training/#{puzzle["id"]}",
        side_to_move: side_to_move(fen)
      }
      begin
        Rails.cache.write("lichess:daily_puzzle", data, expires_in: CACHE_TTL)
      rescue StandardError
        # Cache unavailable — fine, just don't memoize.
      end
      data
    rescue StandardError => e
      Rails.logger.warn("[Lichess::DailyPuzzle] #{e.class}: #{e.message}")
      nil
    end

    # We don't want to ship a full chess engine to compute FENs from PGN
    # plies. Lichess provides initialFen for many puzzles directly in the
    # game object; fall back to the standard starting position if absent.
    def self.fen_from_game(game, _ply)
      game["fen"].presence || game["initialFen"].presence ||
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    end

    def self.side_to_move(fen)
      fen.to_s.split(" ")[1] == "b" ? "black" : "white"
    end
  end
end
