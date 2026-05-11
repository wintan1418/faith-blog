import { Controller } from "@hotwired/stimulus"

// Auto-removes its element after N ms (default 30s) with a soft fade.
// Also exposes a #dismiss action for explicit user dismissals.
export default class extends Controller {
  static values = { afterMs: { type: Number, default: 30000 } }

  connect() {
    this.timer = setTimeout(() => this.fade(), this.afterMsValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss(event) {
    if (event) event.preventDefault()
    this.fade()
  }

  fade() {
    this.element.style.transition = "opacity 400ms ease, transform 400ms ease, height 400ms ease, margin 400ms ease"
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(-4px)"
    setTimeout(() => this.element.remove(), 420)
  }
}
