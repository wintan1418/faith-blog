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

    CACHE_KEY = "lichess:daily_puzzle:v2"

    PRACTICE_ENDPOINT = "https://lichess.org/api/puzzle/next"

    def self.fetch
      cached = Rails.cache.read(CACHE_KEY) rescue nil
      return cached if cached

      data = request_puzzle(ENDPOINT)
      return nil unless data

      begin
        Rails.cache.write(CACHE_KEY, data, expires_in: CACHE_TTL)
      rescue StandardError
        # Cache unavailable — fine, just don't memoize.
      end
      data
    end

    # A fresh random puzzle for unlimited practice — never cached.
    def self.practice
      request_puzzle(PRACTICE_ENDPOINT)
    end

    def self.request_puzzle(endpoint)
      uri = URI(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 4
      http.read_timeout = 5

      response = http.request(Net::HTTP::Get.new(uri))
      return nil unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      puzzle  = payload.dig("puzzle") || {}
      game    = payload.dig("game") || {}
      # Lichess returns the puzzle's starting position directly as
      # puzzle["fen"] — the position right before the solver's first move.
      # The solution is a UCI move list that alternates solver / opponent.
      fen     = puzzle["fen"].presence || fen_from_game(game)
      {
        id:        puzzle["id"],
        rating:    puzzle["rating"].to_i,
        plays:     puzzle["plays"].to_i,
        themes:    Array(puzzle["themes"]),
        solution:  Array(puzzle["solution"]),
        fen:       fen,
        last_move: puzzle["lastMove"].presence,
        link:      "https://lichess.org/training/#{puzzle["id"]}",
        side_to_move: side_to_move(fen)
      }
    rescue StandardError => e
      Rails.logger.warn("[Lichess::DailyPuzzle] #{e.class}: #{e.message}")
      nil
    end

    # Fallback only — used if puzzle["fen"] is somehow missing.
    def self.fen_from_game(game)
      game["fen"].presence || game["initialFen"].presence ||
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    end

    def self.side_to_move(fen)
      fen.to_s.split(" ")[1] == "b" ? "black" : "white"
    end
  end
end
