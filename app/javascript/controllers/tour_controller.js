import { Controller } from "@hotwired/stimulus"

// First-visit tour on the feed: a spotlight on a real part of the page and a
// small card with Back / Next / Skip. No hover anywhere, so it works the same
// with a finger, a mouse, a keyboard and inside the apps.
//
// - Each step names an anchor ([data-tour-anchor="…"]). The first one that is
//   actually on screen wins (lowest data-tour-rank first); a step with none is
//   skipped, so the tour never points at nothing.
// - It waits while a dialog, the Bible drawer, the Discover panel or the
//   splash is open, and steps aside if one opens part-way through.
// - Esc skips; Tab stays inside the card; focus returns where it was.
// - Finishing or skipping tells the server, so it shows once per account.
export default class extends Controller {
  static targets = ["shade", "spot", "pop", "count", "title", "body", "back", "next"]
  static values = { steps: Array, finishUrl: String }

  connect() {
    this.index = -1
    this.active = false
    this.onKey = this.keydown.bind(this)
    this.onMove = () => this.position()
    this.startTimer = setTimeout(() => this.waitThenStart(), 900)
  }

  disconnect() {
    clearTimeout(this.startTimer)
    clearInterval(this.waitTimer)
    this.teardown()
  }

  // ── Starting ──────────────────────────────────────────────────────

  waitThenStart() {
    if (!this.blocked()) return this.start()
    let tries = 0
    this.waitTimer = setInterval(() => {
      tries += 1
      if (!this.blocked()) { clearInterval(this.waitTimer); this.start() }
      else if (tries > 240) clearInterval(this.waitTimer) // give up for this visit (2 min)
    }, 500)
  }

  blocked() {
    const body = document.body
    return Boolean(
      document.querySelector("dialog[open]") ||
      document.getElementById("fc-splash") ||
      body.classList.contains("fc-bible-open") ||
      body.classList.contains("fc-discover-open")
    )
  }

  start() {
    this.steps = this.stepsValue.filter((step) => this.anchorFor(step.anchor))
    if (this.steps.length === 0) return // nothing to point at here; try another visit

    this.returnFocus = document.activeElement
    this.active = true
    this.element.hidden = false
    document.addEventListener("keydown", this.onKey)
    window.addEventListener("resize", this.onMove)
    window.addEventListener("scroll", this.onMove, { passive: true, capture: true })
    // Step aside while something else is open, and come back after.
    this.guard = setInterval(() => {
      const blocked = this.blocked()
      if (blocked !== this.element.hidden) {
        this.element.hidden = blocked
        if (!blocked) this.show(this.index)
      }
    }, 500)
    this.show(0)
  }

  // ── Moving through the steps ──────────────────────────────────────

  next() {
    if (this.index >= this.steps.length - 1) return this.finish()
    this.show(this.index + 1)
  }

  back() {
    if (this.index > 0) this.show(this.index - 1)
  }

  skip() {
    this.finish()
  }

  show(i) {
    const step = this.steps[i]
    // The page may have changed since the tour began: skip a step that lost its anchor.
    this.anchor = step && this.anchorFor(step.anchor)
    if (!this.anchor) {
      if (i < this.steps.length - 1) return this.show(i + 1)
      return this.finish()
    }

    this.index = i
    const last = i === this.steps.length - 1
    this.countTarget.textContent = `Tip ${i + 1} of ${this.steps.length}`
    this.titleTarget.textContent = step.title
    this.bodyTarget.textContent = step.body
    this.backTarget.hidden = i === 0
    this.nextTarget.textContent = last ? "Done" : "Next"

    this.anchor.scrollIntoView({ block: "center", inline: "nearest", behavior: "instant" })
    this.position()
    requestAnimationFrame(() => this.position()) // after any scroll settles
    this.nextTarget.focus({ preventScroll: true })
  }

  // ── Placing the spotlight and the card inside the screen ──────────

  position() {
    if (!this.active || !this.anchor || this.element.hidden) return
    const pad = 6
    const gap = 12
    const edge = 12
    const vw = document.documentElement.clientWidth
    const vh = window.innerHeight
    const r = this.anchor.getBoundingClientRect()

    const top = Math.max(r.top - pad, 4)
    const left = Math.max(r.left - pad, 4)
    const right = Math.min(r.right + pad, vw - 4)
    const bottom = Math.min(r.bottom + pad, vh - 4)
    Object.assign(this.spotTarget.style, {
      top: `${top}px`, left: `${left}px`,
      width: `${Math.max(right - left, 0)}px`, height: `${Math.max(bottom - top, 0)}px`
    })

    const pop = this.popTarget
    const w = pop.offsetWidth
    const h = pop.offsetHeight
    let y
    if (vh - bottom >= h + gap + edge) y = bottom + gap // below
    else if (top >= h + gap + edge) y = top - h - gap // above
    else y = vh - h - edge // tall anchor: sit at the bottom of the screen
    const x = Math.min(Math.max(r.left + r.width / 2 - w / 2, edge), vw - w - edge)
    pop.style.top = `${Math.max(y, edge)}px`
    pop.style.left = `${Math.max(x, edge)}px`
  }

  // First visible element for this anchor name, lowest rank first.
  anchorFor(name) {
    const vw = document.documentElement.clientWidth
    return [...document.querySelectorAll(`[data-tour-anchor="${name}"]`)]
      .filter((el) => {
        if (el.closest("[hidden]") || getComputedStyle(el).visibility === "hidden") return false
        const r = el.getBoundingClientRect()
        return r.width > 0 && r.height > 0 && r.right > 0 && r.left < vw
      })
      .sort((a, b) => Number(a.dataset.tourRank || 0) - Number(b.dataset.tourRank || 0))[0]
  }

  // ── Keyboard ──────────────────────────────────────────────────────

  keydown(event) {
    if (!this.active || this.element.hidden) return
    if (event.key === "Escape") {
      event.preventDefault()
      this.skip()
    } else if (event.key === "Tab") {
      const items = [...this.popTarget.querySelectorAll("button")].filter((b) => !b.hidden)
      const first = items[0]
      const last = items[items.length - 1]
      if (!this.popTarget.contains(document.activeElement)) {
        event.preventDefault()
        first.focus()
      } else if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
  }

  // ── Ending ────────────────────────────────────────────────────────

  finish() {
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    fetch(this.finishUrlValue, {
      method: "POST", credentials: "same-origin", keepalive: true,
      headers: { "X-CSRF-Token": token, Accept: "application/json" }
    }).catch(() => {})
    const back = this.returnFocus
    this.teardown()
    this.element.remove()
    if (back && document.contains(back) && back !== document.body) back.focus({ preventScroll: true })
  }

  teardown() {
    this.active = false
    clearInterval(this.guard)
    document.removeEventListener("keydown", this.onKey)
    window.removeEventListener("resize", this.onMove)
    window.removeEventListener("scroll", this.onMove, { capture: true })
  }
}
