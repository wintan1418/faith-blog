import { Controller } from "@hotwired/stimulus"

// Gamified Bible quiz controller. State machine:
//   modeSelect → loading → question (×N) → result
//
// Tracks live score + streak. Each correct answer flashes mint green and
// emits a combo popup; each miss flashes a soft red. Round time is
// captured for the share line.
export default class extends Controller {
  static targets = ["stage", "modeSelect", "themeGrid", "diffRow", "lengthRow"]
  static values  = { generateUrl: String, submitUrl: String, csrf: String }

  connect() {
    this.theme      = ""
    this.difficulty = ""
    this.length     = 5
    this.bindPickers()
  }

  bindPickers() {
    if (this.hasThemeGridTarget) {
      this.themeGridTarget.querySelectorAll("button").forEach(b => {
        b.addEventListener("click", () => {
          this.themeGridTarget.querySelectorAll("button").forEach(x => x.classList.remove("is-selected"))
          b.classList.add("is-selected")
          this.theme = b.dataset.theme || ""
        })
      })
    }
    if (this.hasDiffRowTarget) {
      this.diffRowTarget.querySelectorAll("button").forEach(b => {
        b.addEventListener("click", () => {
          this.diffRowTarget.querySelectorAll("button").forEach(x => x.classList.remove("is-selected"))
          b.classList.add("is-selected")
          this.difficulty = b.dataset.difficulty || ""
        })
      })
    }
    if (this.hasLengthRowTarget) {
      this.lengthRowTarget.querySelectorAll("button").forEach(b => {
        b.addEventListener("click", () => {
          this.lengthRowTarget.querySelectorAll("button").forEach(x => x.classList.remove("is-selected"))
          b.classList.add("is-selected")
          this.length = parseInt(b.dataset.length, 10) || 5
        })
      })
    }
  }

  async start() {
    this.renderLoading()
    try {
      const url = new URL(this.generateUrlValue, window.location.origin)
      const response = await fetch(url, {
        method: "POST",
        headers: this.headers(),
        credentials: "same-origin",
        body: JSON.stringify({ theme: this.theme, difficulty: this.difficulty, length: this.length })
      })
      const payload = await response.json()
      if (!payload.ok || !Array.isArray(payload.questions) || payload.questions.length === 0) {
        this.renderError(payload.error || "Couldn't fetch a fresh round. Try a different theme or difficulty.")
        return
      }
      this.questions = payload.questions
      this.index = 0
      this.score = 0
      this.streak = 0
      this.bestStreak = 0
      this.answers = []
      this.startedAt = Date.now()
      this.renderQuestion()
    } catch {
      this.renderError("Network error. Try again in a moment.")
    }
  }

  pickChoice(event) {
    const btn = event.currentTarget
    const choice = parseInt(btn.dataset.choice, 10)
    const q = this.questions[this.index]
    const correct = choice === q.correct_index
    if (correct) {
      this.score++
      this.streak++
      if (this.streak > this.bestStreak) this.bestStreak = this.streak
    } else {
      this.streak = 0
    }
    this.answers.push({ index: this.index, picked: choice, correct })

    // Mark choices visually
    const choiceBtns = this.stageTarget.querySelectorAll(".fc-quiz-choice")
    choiceBtns.forEach((b, i) => {
      b.disabled = true
      if (i === q.correct_index) b.classList.add("is-correct")
      if (i === choice && !correct) b.classList.add("is-wrong")
    })

    // Stage flash + streak burst
    this.stageTarget.classList.remove("is-correct", "is-wrong")
    void this.stageTarget.offsetWidth // restart animation
    this.stageTarget.classList.add(correct ? "is-correct" : "is-wrong")

    if (correct && this.streak >= 2) {
      this.flashCombo(this.streak)
    }

    // Update live score + streak HUD
    const scoreEl = this.stageTarget.querySelector(".fc-quiz-hud-score")
    const streakEl = this.stageTarget.querySelector(".fc-quiz-hud-streak")
    if (scoreEl)  scoreEl.textContent  = this.score
    if (streakEl) streakEl.textContent = `🔥 ${this.streak}`

    // Show explanation + next button
    const expl = this.stageTarget.querySelector(".fc-quiz-explanation")
    if (expl) {
      expl.classList.remove("hidden")
      expl.innerHTML = `
        <p class="fc-quiz-verdict ${correct ? "is-right" : "is-miss"}">
          ${correct ? "✓ Right." : "✗ The answer is " + this.escape(q.choices[q.correct_index]) + "."}
        </p>
        ${q.reference ? `<p class="fc-quiz-ref">${this.escape(q.reference)}</p>` : ""}
        ${q.explanation ? `<p class="fc-quiz-note">${this.escape(q.explanation)}</p>` : ""}
      `
    }

    const nextBtn = this.stageTarget.querySelector(".fc-quiz-next")
    if (nextBtn) nextBtn.classList.remove("hidden")
  }

  flashCombo(streak) {
    const burst = document.createElement("div")
    burst.className = "fc-quiz-combo"
    burst.textContent = streak >= 5 ? `🔥 ${streak} ON FIRE` : `🔥 ${streak} in a row`
    this.stageTarget.appendChild(burst)
    setTimeout(() => burst.remove(), 1100)
  }

  next() {
    this.index++
    if (this.index >= this.questions.length) {
      this.finish()
    } else {
      this.renderQuestion()
    }
  }

  async finish() {
    const duration = Date.now() - this.startedAt
    try {
      await fetch(this.submitUrlValue, {
        method: "POST",
        headers: this.headers(),
        credentials: "same-origin",
        body: JSON.stringify({
          score: this.score,
          max_score: this.questions.length,
          duration_ms: duration,
          details: {
            answers: this.answers,
            theme: this.theme,
            difficulty: this.difficulty,
            best_streak: this.bestStreak
          }
        })
      })
    } catch {}
    this.renderResult(duration)
  }

  renderQuestion() {
    const q = this.questions[this.index]
    const n = this.index + 1
    const total = this.questions.length
    const themeTag = q.theme ? q.theme.replace(/_/g, " ") : ""
    const diffTag  = q.difficulty || ""
    this.stageTarget.classList.remove("is-correct", "is-wrong")

    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen fc-quiz-roundscreen">
        <div class="fc-quiz-hud">
          <div class="fc-quiz-hud-left">
            <span class="fc-quiz-hud-progress">Question ${n} / ${total}</span>
            <span class="fc-quiz-hud-tags">
              ${themeTag ? `<span class="fc-quiz-tag is-theme">${this.escape(themeTag)}</span>` : ""}
              ${diffTag  ? `<span class="fc-quiz-tag is-${this.escape(diffTag)}">${this.escape(diffTag)}</span>` : ""}
            </span>
          </div>
          <div class="fc-quiz-hud-right">
            <span class="fc-quiz-hud-score">${this.score}</span>
            <span class="fc-quiz-hud-streak">${this.streak ? `🔥 ${this.streak}` : "·"}</span>
          </div>
        </div>
        <div class="fc-quiz-bar"><span style="width: ${(n / total) * 100}%"></span></div>
        <div class="fc-quiz-card">
          <h2 class="fc-quiz-prompt">${this.escape(q.prompt)}</h2>
          <div class="fc-quiz-choices">
            ${q.choices.map((c, i) => `
              <button type="button"
                      class="fc-quiz-choice"
                      data-action="click->quiz#pickChoice"
                      data-choice="${i}">
                <span class="fc-quiz-choice-letter">${String.fromCharCode(65 + i)}</span>
                <span class="fc-quiz-choice-text">${this.escape(c)}</span>
              </button>
            `).join("")}
          </div>
          <div class="fc-quiz-explanation hidden"></div>
          <button type="button"
                  class="fc-btn fc-btn-primary fc-quiz-next hidden"
                  data-action="click->quiz#next">
            ${this.index + 1 === total ? "See result →" : "Next question →"}
          </button>
        </div>
      </div>
    `
  }

  renderResult(durationMs) {
    const s = this.score
    const t = this.questions.length
    const secs = Math.round(durationMs / 1000)
    const pct = Math.round((s / t) * 100)
    const medal = s === t ? "🏆" : pct >= 80 ? "🥇" : pct >= 60 ? "🥈" : pct >= 40 ? "🥉" : "🌱"
    const verdict = s === t ? "Perfect round."
                   : pct >= 80 ? "Almost flawless."
                   : pct >= 60 ? "Solid run."
                   : pct >= 40 ? "Keep building."
                   : "First step taken."

    const shareLine = `📖 Brethreign Bible Quiz · ${s}/${t} (${pct}%) · ${this.bestStreak} streak · ${secs}s`

    this.stageTarget.classList.remove("is-correct", "is-wrong")
    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen fc-quiz-result">
        <div class="fc-quiz-result-medal">${medal}</div>
        <div class="fc-quiz-result-badge">${s}<span>/${t}</span></div>
        <h2 class="fc-quiz-headline">${this.escape(verdict)}</h2>
        <div class="fc-quiz-result-stats">
          <div class="fc-quiz-stat"><span class="fc-quiz-stat-num">${pct}%</span><span class="fc-quiz-stat-label">Correct</span></div>
          <div class="fc-quiz-stat"><span class="fc-quiz-stat-num">${this.bestStreak}</span><span class="fc-quiz-stat-label">Best streak</span></div>
          <div class="fc-quiz-stat"><span class="fc-quiz-stat-num">${secs}s</span><span class="fc-quiz-stat-label">Time</span></div>
        </div>

        <pre class="fc-quiz-share">${this.escape(shareLine)}</pre>

        <div class="fc-quiz-actions">
          <button type="button" class="fc-btn fc-btn-primary" data-action="click->quiz#copyShare" data-share="${this.escape(shareLine)}">
            ⎘ Copy share line
          </button>
          <button type="button" class="fc-btn" data-action="click->quiz#playAgain">
            Play again
          </button>
          ${this.hasThemeGridTarget ? `
          <button type="button" class="fc-btn" data-action="click->quiz#changeMode">
            Change theme
          </button>` : ""}
          <a href="/games" class="fc-btn">Leaderboard</a>
        </div>
      </div>
    `
  }

  playAgain() {
    // Same theme/difficulty/length, fresh questions
    this.start()
  }

  changeMode() {
    // Back to mode-select with current picks preserved visually
    location.reload()
  }

  async copyShare(event) {
    const btn = event.currentTarget
    const text = btn.dataset.share || ""
    try {
      await navigator.clipboard.writeText(text)
      const original = btn.innerHTML
      btn.innerHTML = "✓ Copied"
      setTimeout(() => { btn.innerHTML = original }, 1400)
    } catch {}
  }

  renderLoading() {
    this.stageTarget.classList.remove("is-correct", "is-wrong")
    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen">
        <p class="fc-quiz-kicker">Lining up a fresh round…</p>
        <div class="fc-skel fc-quiz-skel" style="height: 18px; width: 60%;"></div>
        <div class="fc-skel fc-quiz-skel" style="height: 56px;"></div>
        <div class="fc-skel fc-quiz-skel" style="height: 56px;"></div>
        <div class="fc-skel fc-quiz-skel" style="height: 56px;"></div>
        <div class="fc-skel fc-quiz-skel" style="height: 56px;"></div>
      </div>
    `
  }

  renderError(msg) {
    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen">
        <p class="fc-quiz-headline">Couldn't load the round.</p>
        <p class="fc-quiz-sub">${this.escape(msg)}</p>
        <button type="button" class="fc-btn fc-btn-primary" data-action="click->quiz#changeMode">Back to setup</button>
      </div>
    `
  }

  headers() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": this.csrfValue || document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"})[c])
  }
}
