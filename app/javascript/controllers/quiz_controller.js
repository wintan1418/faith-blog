import { Controller } from "@hotwired/stimulus"

// Bible quiz state machine. Fetches 5 questions on Start, walks through
// one at a time, scores live, submits the attempt at the end, and shows
// a shareable result. Unlimited replays — each counts on the leaderboard.
export default class extends Controller {
  static targets = ["stage", "ready"]
  static values  = { generateUrl: String, submitUrl: String, csrf: String }

  start() {
    this.fetchQuiz()
  }

  async fetchQuiz() {
    this.renderLoading()
    try {
      const response = await fetch(this.generateUrlValue, {
        method: "POST",
        headers: this.headers(),
        credentials: "same-origin",
        body: "{}"
      })
      const payload = await response.json()
      if (!payload.ok) {
        this.renderError(payload.error || "Couldn't load a quiz right now.")
        return
      }
      this.questions = payload.questions
      this.index = 0
      this.score = 0
      this.answers = []
      this.startedAt = Date.now()
      this.renderQuestion()
    } catch (e) {
      this.renderError("Network error. Try again in a moment.")
    }
  }

  pickChoice(event) {
    const btn = event.currentTarget
    const choice = parseInt(btn.dataset.choice, 10)
    const q = this.questions[this.index]
    const correct = choice === q.correct_index
    if (correct) this.score++
    this.answers.push({ index: this.index, picked: choice, correct })

    // Mark choices visually
    const choiceBtns = this.stageTarget.querySelectorAll(".fc-quiz-choice")
    choiceBtns.forEach((b, i) => {
      b.disabled = true
      if (i === q.correct_index) b.classList.add("is-correct")
      if (i === choice && !correct) b.classList.add("is-wrong")
    })

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
    // Submit attempt
    try {
      await fetch(this.submitUrlValue, {
        method: "POST",
        headers: this.headers(),
        credentials: "same-origin",
        body: JSON.stringify({
          score: this.score,
          max_score: this.questions.length,
          duration_ms: duration,
          details: { answers: this.answers }
        })
      })
    } catch {}
    this.renderResult(duration)
  }

  renderQuestion() {
    const q = this.questions[this.index]
    const n = this.index + 1
    const total = this.questions.length
    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen">
        <div class="fc-quiz-progress">
          <span>Question ${n} of ${total}</span>
          <span class="fc-quiz-score">Score · ${this.score}</span>
        </div>
        <div class="fc-quiz-bar"><span style="width: ${(n / total) * 100}%"></span></div>
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
    `
  }

  renderResult(durationMs) {
    const s = this.score
    const t = this.questions.length
    const secs = Math.round(durationMs / 1000)
    const pct = Math.round((s / t) * 100)
    const verdict = s === t ? "Perfect."
                  : s >= t - 1 ? "Almost flawless."
                  : s >= Math.ceil(t / 2) ? "Solid."
                  : "Keep at it — try again."

    const shareLine = `📖 Brethreign Bible Quiz · ${s}/${t} (${pct}%) · ${secs}s`

    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen fc-quiz-result">
        <div class="fc-quiz-result-badge">${s}/${t}</div>
        <h2 class="fc-quiz-headline">${this.escape(verdict)}</h2>
        <p class="fc-quiz-sub">${pct}% correct in ${secs} seconds. Attempt saved to the leaderboard.</p>

        <pre class="fc-quiz-share">${this.escape(shareLine)}</pre>

        <div class="fc-quiz-actions">
          <button type="button" class="fc-btn fc-btn-primary" data-action="click->quiz#copyShare" data-share="${this.escape(shareLine)}">
            ⎘ Copy share line
          </button>
          <button type="button" class="fc-btn" data-action="click->quiz#start">
            Play again
          </button>
          <a href="/games" class="fc-btn">Leaderboard</a>
        </div>
      </div>
    `
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
    this.stageTarget.innerHTML = `
      <div class="fc-quiz-screen">
        <p class="fc-quiz-kicker">Fetching a fresh round…</p>
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
        <p class="fc-quiz-headline">Couldn't load the quiz.</p>
        <p class="fc-quiz-sub">${this.escape(msg)}</p>
        <button type="button" class="fc-btn fc-btn-primary" data-action="click->quiz#start">Try again</button>
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
