import { Controller } from "@hotwired/stimulus"
import { loadChess } from "../lazy_libs"

// Chess puzzles, played fully in-app. chess.js handles move legality.
//
// Daily puzzle: today's Lichess puzzle; solving it claims points once a day.
// The ladder: 10 stages that get harder as you climb, at Easy, Medium or Hard.
//
// Every puzzle gives 3 tries. A wrong move is played, then taken back, and
// costs a try; a hint costs a try too. Out of tries shows the solution (and
// in the ladder ends the climb). Any move that gives checkmate counts, not
// only the one Lichess lists.
const GLYPH = { p: "♟", n: "♞", b: "♝", r: "♜", q: "♛", k: "♚" }
const TRIES = 3
const STAGES = 10
const STEPS = [ "easiest", "easier", "normal", "harder", "hardest" ]
// Where each level starts on Lichess's difficulty steps; the climb adds one
// step every few stages.
const LEVELS = { easy: 0, medium: 1, hard: 3 }
const BEST_KEY = "brethreign:chess-ladder-best"

export default class extends Controller {
  static targets = [ "board", "status", "feedback", "progress", "hintBtn", "resetBtn", "kicker", "rating", "themes", "tier",
                     "tries", "stage", "best", "level", "nextBtn" ]
  static values  = {
    fen:         String,
    solution:    Array,
    lastMove:    String,
    solvedUrl:   String,
    practiceUrl: String,
    csrf:        String,
    already:     Boolean
  }

  connect() {
    let solution = []
    try { solution = this.solutionValue } catch { solution = [] }
    this.puzzle = {
      fen: (this.fenValue || "").trim(),
      solution: Array.isArray(solution) ? solution : [],
      lastMove: (this.lastMoveValue || "").trim()
    }
    this.mode = "daily"            // "daily" | "ladder"
    this.level = "medium"
    this.stage = 0
    this.showBest()
    this.markLevel()
    loadChess().then((Chess) => {
      this.Chess = Chess
      this.start()
    }).catch((err) => {
      console.error("[chess-puzzle] could not start:", err)
      this.showLoadError(err)
    })
  }

  start() {
    if (!this.puzzle.fen) throw new Error("missing puzzle FEN")
    this.solution = this.puzzle.solution
    if (this.solution.length === 0) throw new Error("missing puzzle solution")

    // Each start is a new run: a "Show solution" animation, a wrong move
    // waiting to be taken back, or an opponent reply still pending from the
    // previous run must not touch this board.
    this.run = (this.run || 0) + 1
    this.game = new this.Chess(this.puzzle.fen)
    this.idx = 0
    this.selected = null
    this.legalTargets = []
    this.lastMove = null
    this.complete = false
    this.revealed = false
    this.failed = false
    this.busy = false
    this.triesLeft = TRIES

    // Some Lichess payloads give the position BEFORE the opponent's last
    // move. If the first solution move isn't legal here, play lastMove first.
    const s0 = this.parseUci(this.solution[0])
    const s0Legal = this.game.moves({ verbose: true }).some(m => m.from === s0.from && m.to === s0.to)
    if (!s0Legal && this.puzzle.lastMove) {
      const lm = this.parseUci(this.puzzle.lastMove)
      try {
        this.game.move({ from: lm.from, to: lm.to, promotion: lm.promotion || "q" })
        this.lastMove = { from: lm.from, to: lm.to }
      } catch { /* leave the position as given */ }
    }

    this.solverColor = this.game.turn()
    this.renderBoard()
    this.renderTries()
    this.setNextButton(false)
    this.setStatus(`${this.colorName(this.solverColor)} to move. Find the best move.`)
    this.updateProgress()
    if (this.hasFeedbackTarget) this.feedbackTarget.classList.add("hidden")
  }

  // ─── The ladder ──────────────────────────────────────────────
  chooseLevel(event) {
    const level = event.currentTarget.dataset.level
    if (!LEVELS.hasOwnProperty(level)) return
    this.level = level
    this.markLevel()
    this.showBest()
    this.startLadder()
  }

  startLadder() {
    this.stage = 1
    this.loadStage()
  }

  nextStage() {
    if (this.mode !== "ladder" || !this.complete || this.failed) return this.startLadder()
    if (this.stage >= STAGES) return this.startLadder()
    this.stage += 1
    this.loadStage()
  }

  difficultyFor(stage) {
    const step = Math.min(LEVELS[this.level] + Math.floor((stage - 1) / 4), STEPS.length - 1)
    return STEPS[step]
  }

  async loadStage() {
    if (!this.practiceUrlValue) return
    this.mode = "ladder"
    this.setStatus(`Setting up stage ${this.stage}…`)
    this.setNextButton(false)
    try {
      const url = new URL(this.practiceUrlValue, location.origin)
      url.searchParams.set("difficulty", this.difficultyFor(this.stage))
      const resp = await fetch(url, { headers: { "Accept": "application/json" }, credentials: "same-origin" })
      const data = await resp.json()
      if (!data.ok || !data.puzzle) throw new Error(data.error || "no puzzle")
      this.puzzle = {
        fen: data.puzzle.fen || "",
        solution: Array.isArray(data.puzzle.solution) ? data.puzzle.solution : [],
        lastMove: data.puzzle.last_move || ""
      }
      this.start()
      this.showLadderHeader(data.puzzle)
    } catch (err) {
      this.flash("bad", "Couldn't load the next puzzle. Check your connection and tap the button again.")
      this.setNextButton(true, "Try again")
      this.stage = Math.max(this.stage - 1, 0)
      this.complete = true
    }
  }

  showLadderHeader(puzzle) {
    const side = this.colorName(this.solverColor)
    const levelName = this.level[0].toUpperCase() + this.level.slice(1)
    if (this.hasKickerTarget) this.kickerTarget.textContent = `Ladder · ${levelName} · ${side} to move`
    if (this.hasRatingTarget) this.ratingTarget.textContent = `Stage ${this.stage} of ${STAGES}`
    if (this.hasThemesTarget) {
      this.themesTarget.textContent = `Rating ${puzzle.rating} · ` + (puzzle.themes || []).slice(0, 3)
        .map(t => t.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/^./, c => c.toUpperCase())).join(" · ")
    }
    if (this.hasTierTarget) this.tierTarget.style.display = "none" // ladder has no points
    if (this.hasStageTarget) {
      this.stageTarget.hidden = false
      this.stageTarget.querySelectorAll("i").forEach((dot, i) => {
        dot.classList.toggle("is-done", i < this.stage - 1)
        dot.classList.toggle("is-now", i === this.stage - 1)
      })
    }
  }

  markLevel() {
    if (!this.hasLevelTarget) return
    this.levelTargets.forEach(btn => {
      const on = btn.dataset.level === this.level
      btn.classList.toggle("is-on", on)
      btn.setAttribute("aria-pressed", on ? "true" : "false")
    })
  }

  bestStages() {
    try { return JSON.parse(localStorage.getItem(BEST_KEY) || "{}") } catch { return {} }
  }

  saveBest(stage) {
    const best = this.bestStages()
    if ((best[this.level] || 0) >= stage) return
    best[this.level] = stage
    try { localStorage.setItem(BEST_KEY, JSON.stringify(best)) } catch { /* private mode */ }
    this.showBest()
  }

  showBest() {
    if (!this.hasBestTarget) return
    const best = this.bestStages()[this.level]
    this.bestTarget.textContent = best ? `Your best: stage ${best} of ${STAGES}` : "Climb as high as you can."
  }

  // ─── Reveal: watch the solution play out ─────────────────────
  async revealSolution() {
    if (this.complete) return
    this.giveUp("Here's the line.")
  }

  async giveUp(message) {
    const run = this.run
    this.revealed = true
    this.complete = true
    this.clearSelection()
    this.setStatus(message)
    while (this.idx < this.solution.length) {
      if (run !== this.run) return
      const m = this.parseUci(this.solution[this.idx])
      try { this.game.move({ from: m.from, to: m.to, promotion: m.promotion || "q" }) } catch { break }
      this.lastMove = { from: m.from, to: m.to }
      this.idx += 1
      this.renderBoard()
      this.updateProgress()
      await new Promise(r => setTimeout(r, 650))
    }
    if (run !== this.run) return

    if (this.mode === "ladder") {
      this.failed = true
      const reached = this.stage - 1
      if (reached > 0) this.saveBest(reached)
      this.flash("bad", reached > 0 ? `The climb ends at stage ${this.stage}. You cleared ${reached}.` : "The climb ends here.")
      this.showFeedback("Every stage is a new puzzle, so the next climb is different. Try again?")
      this.setNextButton(true, "Climb again")
    } else {
      this.flash("hint", "That was the line. No points this time; try the ladder below.")
    }
  }

  reset() {
    if (this.mode === "ladder" && this.failed) {
      this.flash("hint", "This climb is over. Tap “Climb again” to start a new one.")
      return
    }
    // Restart puts the pieces back but keeps the tries you've used.
    const left = this.complete ? undefined : this.triesLeft
    try {
      this.start()
      if (left !== undefined) { this.triesLeft = left; this.renderTries() }
    } catch (err) {
      console.error("[chess-puzzle] could not reset:", err)
      this.showLoadError(err)
    }
  }

  showLoadError(err) {
    if (this.hasStatusTarget) {
      this.statusTarget.className = "fc-chess-status is-bad"
      this.statusTarget.textContent = "Couldn't load the board here. Use “View on Lichess” below to solve today's puzzle."
    }
    if (this.hasFeedbackTarget) {
      const detail = (err && (err.message || err.toString())) || "unknown error"
      this.feedbackTarget.classList.remove("hidden")
      this.feedbackTarget.textContent = `Diagnostic: ${detail}`
    }
  }

  // ─── Rendering ───────────────────────────────────────────────
  renderBoard() {
    const board = this.game.board()
    const flip  = this.solverColor === "b"
    const order = flip ? [ 7, 6, 5, 4, 3, 2, 1, 0 ] : [ 0, 1, 2, 3, 4, 5, 6, 7 ]

    const frag = document.createDocumentFragment()
    for (const r of order) {
      for (const f of order) {
        const cell   = board[r][f]
        const square = "abcdefgh"[f] + (8 - r)
        const sq = document.createElement("button")
        sq.type = "button"
        sq.className = "fc-chess-sq " + (((r + f) % 2 === 0) ? "is-light" : "is-dark")
        sq.dataset.square = square
        if (this.selected === square) sq.classList.add("is-selected")
        if (this.legalTargets.includes(square)) sq.classList.add(cell ? "is-capture" : "is-target")
        if (this.lastMove && (this.lastMove.from === square || this.lastMove.to === square)) {
          sq.classList.add(this.lastMove.wrong ? "is-wrong" : "is-lastmove")
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
    this.boardTarget.textContent = ""
    this.boardTarget.appendChild(frag)
  }

  renderTries() {
    if (!this.hasTriesTarget) return
    const hearts = Array.from({ length: TRIES }, (_, i) => (i < this.triesLeft ? "❤️" : "🤍")).join("")
    this.triesTarget.textContent = hearts
    this.triesTarget.setAttribute("aria-label", `${this.triesLeft} of ${TRIES} tries left`)
  }

  setNextButton(show, label) {
    if (!this.hasNextBtnTarget) return
    this.nextBtnTarget.hidden = !show
    if (label) this.nextBtnTarget.textContent = label
  }

  // ─── Interaction ─────────────────────────────────────────────
  onSquareClick(square) {
    if (this.complete || this.busy) return
    if (this.game.turn() !== this.solverColor) return

    const piece = this.game.get(square)

    if (this.selected) {
      if (square === this.selected) { this.clearSelection(); this.renderBoard(); return }
      if (this.legalTargets.includes(square)) { this.tryUserMove(this.selected, square); return }
      if (piece && piece.color === this.solverColor) { this.select(square); this.renderBoard(); return }
      this.clearSelection(); this.renderBoard(); return
    }

    if (piece && piece.color === this.solverColor) {
      this.select(square)
      this.renderBoard()
    } else if (piece) {
      const side = this.colorName(this.solverColor)
      this.flash("hint", `It's ${side} to move. Tap a ${side.toLowerCase()} piece.`)
    }
  }

  select(square) {
    this.selected = square
    this.legalTargets = this.game.moves({ square, verbose: true }).map(m => m.to)
  }

  clearSelection() {
    this.selected = null
    this.legalTargets = []
  }

  tryUserMove(from, to) {
    const expected = this.parseUci(this.solution[this.idx])
    const promotion = expected.promotion || "q"
    this.clearSelection()

    let move
    try { move = this.game.move({ from, to, promotion }) } catch { move = null }
    if (!move) { this.renderBoard(); return }

    const isSolution = from === expected.from && to === expected.to
    // Any checkmate wins, even if Lichess lists a different mating move.
    const mates = this.game.isCheckmate()

    if (isSolution || mates) {
      this.lastMove = { from, to }
      this.idx += 1
      this.renderBoard()
      this.updateProgress()
      if (mates || this.idx >= this.solution.length) return this.finish()

      this.flash("good", "Correct. Keep going.")
      const run = this.run
      setTimeout(() => { if (run === this.run) this.autoOpponentMove() }, 450)
      return
    }

    // A legal move that isn't the answer: show it, take it back, lose a try.
    this.lastMove = { from, to, wrong: true }
    this.renderBoard()
    this.busy = true
    this.loseTry("Not the best move here.")
    const run = this.run
    setTimeout(() => {
      if (run !== this.run) return
      this.game.undo()
      this.lastMove = null
      this.busy = false
      this.renderBoard()
    }, 700)
  }

  loseTry(reason) {
    this.triesLeft = Math.max(this.triesLeft - 1, 0)
    this.renderTries()
    if (this.triesLeft === 0) {
      const run = this.run
      setTimeout(() => { if (run === this.run) this.giveUp(`${reason} Out of tries. Here's the line.`) }, 750)
      return false
    }
    this.flash("bad", `${reason} ${this.triesLeft} ${this.triesLeft === 1 ? "try" : "tries"} left.`)
    return true
  }

  autoOpponentMove() {
    const uci = this.solution[this.idx]
    if (!uci) return
    const m = this.parseUci(uci)
    this.game.move({ from: m.from, to: m.to, promotion: m.promotion || "q" })
    this.lastMove = { from: m.from, to: m.to }
    this.idx += 1
    this.renderBoard()
    this.updateProgress()

    if (this.idx >= this.solution.length) this.finish()
    else this.setStatus("Your move.")
  }

  showHint() {
    if (this.complete || this.busy || this.game.turn() !== this.solverColor) return
    if (this.triesLeft <= 1) {
      this.flash("hint", "A hint costs a try, and this is your last one. You've got this.")
      return
    }
    const expected = this.parseUci(this.solution[this.idx])
    this.select(expected.from)
    this.renderBoard()
    this.triesLeft -= 1
    this.renderTries()
    this.flash("hint", `Try the piece on ${expected.from}. (A hint costs a try.)`)
  }

  // ─── Finish ──────────────────────────────────────────────────
  finish() {
    this.complete = true
    this.clearSelection()

    if (this.mode === "ladder") {
      this.saveBest(this.stage)
      if (this.stage >= STAGES) {
        this.flash("good", `Ladder complete. All ${STAGES} stages cleared! 🏆`)
        this.showFeedback("Try the next level up for a harder climb.")
        this.setNextButton(true, "Climb again")
      } else {
        this.flash("good", `Stage ${this.stage} cleared. The next one is a little harder.`)
        this.setNextButton(true, `Stage ${this.stage + 1} →`)
      }
      return
    }

    this.flash("good", "Puzzle solved. Well played.")
    if (this.revealed) return this.showFeedback("Solution shown: no points this time, but now you've seen the idea.")
    if (this.alreadyValue) return this.showFeedback("You already claimed today's points. Now try the ladder below.")
    this.recordSolved()
  }

  async recordSolved() {
    try {
      const resp = await fetch(this.solvedUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": this.csrfValue },
        credentials: "same-origin"
      })
      const data = await resp.json()
      if (data.ok) {
        this.alreadyValue = true
        this.showFeedback(`+${data.score} points added. Now try the ladder below, or come back tomorrow.`)
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
    const total = Math.ceil(this.solution.length / 2) // your moves only
    const done  = Math.min(Math.ceil(this.idx / 2), total)
    this.progressTarget.textContent = this.complete ? `${total} of ${total} moves` : `Move ${Math.min(done + 1, total)} of ${total}`
  }
}
