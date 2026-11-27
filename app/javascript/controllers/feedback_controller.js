import { Controller } from "@hotwired/stimulus"

// A feedback survey (FeedbackCampaign). Two uses:
//  - the survey page (from the alert): picking a rating turns on Submit;
//  - the feed pop-up (prompt: true): a bottom sheet that slides in after the
//    member has read ~8 posts or ~20 seconds, never while they're typing or
//    have a dialog (composer, What's new…) open. "Not now" snoozes it for two
//    days, "Don't ask again" ends it for this survey.
export default class extends Controller {
  static targets = ["rating", "submit", "thanks", "question", "bar", "count", "needs"]
  static values = {
    prompt: Boolean,
    delayMs: { type: Number, default: 20000 },
    afterPosts: { type: Number, default: 8 },
    snoozeUrl: String,
    declineUrl: String
  }

  connect() {
    this.syncRating()
    this.progress()
    if (!this.promptValue) return

    this.element.hidden = true
    this.readMs = 0
    this.tick = setInterval(() => {
      if (document.visibilityState !== "visible") return
      this.readMs += 1000
      if (this.readMs >= this.delayMsValue) this.ready()
    }, 1000)
    this.watchPosts()
  }

  disconnect() {
    clearInterval(this.tick)
    clearTimeout(this.retry)
    clearTimeout(this.autoHide)
    this.observer?.disconnect()
  }

  // ── Pop-up ────────────────────────────────────────────────

  watchPosts() {
    const cards = document.querySelectorAll("#feed_list article.fc-card")
    if (!cards.length || !("IntersectionObserver" in window)) return

    const target = cards[Math.min(this.afterPostsValue, cards.length) - 1]
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) this.ready()
    })
    this.observer.observe(target)
  }

  ready() {
    if (this.shown) return
    clearInterval(this.tick)
    this.observer?.disconnect()
    if (this.busy()) {
      clearTimeout(this.retry)
      this.retry = setTimeout(() => this.ready(), 5000)
      return
    }
    this.shown = true
    this.element.hidden = false
    requestAnimationFrame(() => this.element.classList.add("is-open"))
  }

  // Typing, or a dialog, drawer or the first-visit tour is open: don't interrupt.
  busy() {
    const active = document.activeElement
    if (active && (active.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName) || active.tagName === "TRIX-EDITOR")) {
      return !this.element.contains(active)
    }
    const body = document.body
    return Boolean(
      document.querySelector("dialog[open]") ||
      document.querySelector("[data-controller~='tour']:not([hidden])") ||
      document.getElementById("fc-splash") ||
      body.classList.contains("fc-bible-open") ||
      body.classList.contains("fc-discover-open")
    )
  }

  later(event) {
    event?.preventDefault()
    this.send(this.snoozeUrlValue)
    this.hide()
  }

  never(event) {
    event?.preventDefault()
    this.send(this.declineUrlValue)
    this.hide()
  }

  hide() {
    if (!this.promptValue) return
    this.element.classList.remove("is-open")
    setTimeout(() => { this.element.hidden = true }, 320)
  }

  // After "Thank you" arrives, the sheet slides away on its own.
  thanksTargetConnected() {
    if (this.promptValue) this.autoHide = setTimeout(() => this.hide(), 4500)
  }

  send(url) {
    if (!url) return
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    fetch(url, { method: "POST", credentials: "same-origin", keepalive: true, headers: { "X-CSRF-Token": token, Accept: "text/plain" } })
      .catch(() => {})
  }

  // ── Rating ────────────────────────────────────────────────

  pick() {
    this.syncRating()
  }

  syncRating() {
    const inputs = this.ratingTargets
    const picked = inputs.findIndex((input) => input.checked)
    inputs.forEach((input, i) => {
      input.closest("label")?.classList.toggle("is-lit", picked >= 0 && i <= picked)
      input.closest("label")?.classList.toggle("is-picked", i === picked)
    })
    if (this.hasSubmitTarget) this.submitTarget.disabled = picked < 0
    if (this.hasNeedsTarget) this.needsTarget.hidden = picked >= 0
  }

  // ── Longer surveys ────────────────────────────────────────

  // "5 of 12 answered" and the bar above the questions.
  progress(event) {
    const q = event?.target?.closest?.(".fb-q.is-missing")
    if (q && q.querySelector("input:checked")) {
      q.classList.remove("is-missing")
      q.querySelector(".fb-q-missing")?.setAttribute("hidden", "")
    }
    if (!this.hasCountTarget) return
    const total = this.questionTargets.length
    const done = this.questionTargets.filter((q) =>
      q.querySelector("input:checked") || [...q.querySelectorAll("textarea")].some((t) => t.value.trim())
    ).length
    this.countTarget.textContent = `${done} of ${total} answered`
    if (this.hasBarTarget) this.barTarget.style.width = `${total ? (done / total) * 100 : 0}%`
  }

  // Before sending: jump to the first required question left blank.
  check(event) {
    let first = null
    this.questionTargets.forEach((q) => {
      const missing = q.dataset.required === "true" && !q.querySelector("input:checked")
      q.classList.toggle("is-missing", missing)
      const note = q.querySelector(".fb-q-missing")
      if (note) note.hidden = !missing
      if (missing && !first) first = q
    })
    if (!first) return
    event.preventDefault()
    first.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  // "Pick up to 3": a fourth tick is undone.
  limit(event) {
    const box = event.target
    const row = box.closest("[data-max]")
    if (!row || !box.checked) return
    const max = Number(row.dataset.max)
    if (row.querySelectorAll("input:checked").length > max) box.checked = false
  }
}
