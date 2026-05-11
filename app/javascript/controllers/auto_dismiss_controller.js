import { Controller } from "@hotwired/stimulus"

// Auto-removes its element after N ms (default 30s) with a soft fade.
// If `persistKey` is set, the dismissal is remembered in localStorage so
// the element stays gone across page loads (server re-renders it, we hide
// it immediately on connect).
export default class extends Controller {
  static values = {
    afterMs: { type: Number, default: 30000 },
    persistKey: String,
    storeKey:   { type: String, default: "fc:dismissed" }
  }

  connect() {
    if (this.persistKeyValue && this.isDismissed()) {
      this.element.style.display = "none"
      return
    }
    this.timer = setTimeout(() => this.fade({ persist: true }), this.afterMsValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss(event) {
    if (event) event.preventDefault()
    this.fade({ persist: true })
  }

  fade({ persist } = {}) {
    if (persist && this.persistKeyValue) this.recordDismissal()
    this.element.style.transition = "opacity 400ms ease, transform 400ms ease, height 400ms ease, margin 400ms ease"
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(-4px)"
    setTimeout(() => this.element.remove(), 420)
  }

  isDismissed() {
    try {
      const raw = localStorage.getItem(this.storeKeyValue)
      const set = raw ? JSON.parse(raw) : {}
      return Boolean(set[this.persistKeyValue])
    } catch {
      return false
    }
  }

  recordDismissal() {
    try {
      const raw = localStorage.getItem(this.storeKeyValue)
      const set = raw ? JSON.parse(raw) : {}
      set[this.persistKeyValue] = Date.now()
      // Trim entries older than 60 days so the dictionary doesn't grow forever.
      const cutoff = Date.now() - 60 * 24 * 60 * 60 * 1000
      for (const k of Object.keys(set)) if (set[k] < cutoff) delete set[k]
      localStorage.setItem(this.storeKeyValue, JSON.stringify(set))
    } catch {
      // localStorage full / disabled — ignore
    }
  }
}
