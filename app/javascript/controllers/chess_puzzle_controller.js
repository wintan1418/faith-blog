import { Controller } from "@hotwired/stimulus"
import { Chess } from "chess.js"

// Daily chess puzzle — played fully in-app. The board is rendered from
// the Lichess puzzle FEN; chess.js handles move legality. The user must
// find each move of the solution; opponent replies auto-play. Solving
// the whole line records a GameAttempt (unless already claimed today).
const GLYPH = { p: "♟", n: "♞", b: "♝", r: "♜", q: "♛", k: "♚" }

export default class extends Controller {
  static targets = ["board", "status", "feedback", "progress", "hintBtn", "resetBtn"]
  static values  = {
    fen:       String,
    solution:  Array,
    solvedUrl: String,
    csrf:      String,
    already:   Boolean
  }

  connect() {
    this.start()
  }

  start() {
    this.game = new Chess(this.fenValue)
    this.solverColor = this.game.turn()         // side to move in the puzzle FEN
    this.idx = 0                                // index into the solution list
    this.selected = null
    this.targets = []
    this.lastMove = null
    this.complete = false
    this.renderBoard()
    this.setStatus(`${this.colorName(this.solverColor)} to move — find the strongest line.`)
    this.updateProgress()
    if (this.hasFeedbackTarget) this.feedbackTarget.classList.add("hidden")
  }

  reset() {
    this.start()
  }

  // ─── Rendering ───────────────────────────────────────────────
  renderBoard() {
    const board = this.game.board()             // [rank8 … rank1][fileA … fileH]
    const flip  = this.solverColor === "b"
    const rankOrder = flip ? [7, 6, 5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5, 6, 7]
    const fileOrder = flip ? [7, 6, 5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5, 6, 7]

    const frag = document.createDocumentFragment()
    for (const r of rankOrder) {
      for (const f of fileOrder) {
        const cell    = board[r][f]
        const square  = "abcdefgh"[f] + (8 - r)
        const sq = document.createElement("button")
        sq.type = "button"
        sq.className = "fc-chess-sq " + (((r + f) % 2 === 0) ? "is-light" : "is-dark")
        sq.dataset.square = square
        if (this.selected === square)   sq.classList.add("is-selected")
        if (this.targets.includes(square)) sq.classList.add(cell ? "is-capture" : "is-target")
        if (this.lastMove && (this.lastMove.from === square || this.lastMove.to === square)) {
          sq.classList.add("is-lastmove")
        }
        if (cell) {
          const piece = document.createElement("span")
          piece.className = `fc-chess-piece is-${cell.color}`
          piece.textContent = GLYPH[cell.type]
          sq.appendChild(piece)
        }
        sq.addEventListener("click", () => this.onSquareClick(square))
        frag.appendChild(sq)
      }
    }
    this.boardTarget.replaceChildren(frag)
  }

  // ─── Interaction ─────────────────────────────────────────────
  onSquareClick(square) {
    if (this.complete) return
    if (this.game.turn() !== this.solverColor) return  // opponent's turn — wait

    const piece = this.game.get(square)

    if (this.selected) {
      if (square === this.selected) { this.clearSelection(); this.renderBoard(); return }
      if (this.targets.includes(square)) { this.tryUserMove(this.selected, square); return }
      if (piece && piece.color === this.solverColor) { this.select(square); this.renderBoard(); return }
      this.clearSelection(); this.renderBoard(); return
    }

    if (piece && piece.color === this.solverColor) {
      this.select(square)
      this.renderBoard()
    }
  }

  select(square) {
    this.selected = square
    this.targets = this.game.moves({ square, verbose: true }).map(m => m.to)
  }

  clearSelection() {
    this.selected = null
    this.targets = []
  }

  tryUserMove(from, to) {
    const expected = this.parseUci(this.solutionValue[this.idx])
    if (from !== expected.from || to !== expected.to) {
      this.clearSelection()
      this.renderBoard()
      this.flash("bad", "Not the puzzle move — look again.")
      return
    }

    this.game.move({ from, to, promotion: expected.promotion || "q" })
    this.lastMove = { from, to }
    this.idx += 1
    this.clearSelection()
    this.renderBoard()
    this.updateProgress()

    if (this.idx >= this.solutionValue.length) {
      this.finish()
      return
    }

    this.flash("good", "Correct — keep going.")
    setTimeout(() => this.autoOpponentMove(), 450)
  }

  autoOpponentMove() {
    const uci = this.solutionValue[this.idx]
    if (!uci) return
    const m = this.parseUci(uci)
    this.game.move({ from: m.from, to: m.to, promotion: m.promotion || "q" })
    this.lastMove = { from: m.from, to: m.to }
    this.idx += 1
    this.renderBoard()
    this.updateProgress()

    if (this.idx >= this.solutionValue.length) {
      this.finish()
    } else {
      this.setStatus("Your move.")
    }
  }

  showHint() {
    if (this.complete || this.game.turn() !== this.solverColor) return
    const expected = this.parseUci(this.solutionValue[this.idx])
    this.select(expected.from)
    this.renderBoard()
    this.flash("hint", `Try the piece on ${expected.from}.`)
  }

  // ─── Finish ──────────────────────────────────────────────────
  finish() {
    this.complete = true
    this.clearSelection()
    this.flash("good", "Puzzle solved — well played.")

    if (this.alreadyValue) {
      this.showFeedback("You already claimed today's points — nice replay though.")
      return
    }
    this.recordSolved()
  }

  async recordSolved() {
    try {
      const resp = await fetch(this.solvedUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        credentials: "same-origin"
      })
      const data = await resp.json()
      if (data.ok) {
        this.alreadyValue = true
        this.showFeedback(`+${data.score} points added. Come back tomorrow for the next puzzle.`)
      } else {
        this.showFeedback(data.error || "Couldn't record your solve.")
      }
    } catch {
      this.showFeedback("Network error while recording your solve.")
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────
  parseUci(uci) {
    return { from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] }
  }

  colorName(c) {
    return c === "w" ? "White" : "Black"
  }

  setStatus(msg) {
    this.statusTarget.className = "fc-chess-status"
    this.statusTarget.textContent = msg
  }

  flash(kind, msg) {
    this.statusTarget.className = `fc-chess-status is-${kind}`
    this.statusTarget.textContent = msg
  }

  showFeedback(msg) {
    if (!this.hasFeedbackTarget) return
    this.feedbackTarget.textContent = msg
    this.feedbackTarget.classList.remove("hidden")
  }

  updateProgress() {
    if (!this.hasProgressTarget) return
    const total = this.solutionValue.length
    const done  = Math.min(this.idx, total)
    this.progressTarget.textContent = `Move ${Math.min(done + (this.complete ? 0 : 1), total)} of ${total}`
  }
}
